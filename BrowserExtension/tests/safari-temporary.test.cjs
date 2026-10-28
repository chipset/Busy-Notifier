const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function connection(config, fetch) {
  const context={browser:{storage:{local:{get:async()=>({meetingBusyBridge:config})}}},
    crypto:{randomUUID:()=> 'session-id'},fetch,AbortSignal:{timeout:()=> 'timeout'}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../safari-temporary/safari-transport.js'),'utf8'),context);
  return context.MeetingBusySafariTransport.connect();
}
test('temporary Safari transport pairs only to loopback and returns app policy',async()=>{
  const requests=[], received=[];
  const config={port:48157,token:'a'.repeat(64)};
  const port=connection(config,async(url,options)=>{requests.push({url,options});return {ok:true,json:async()=>({accepted:true})};});
  port.onMessage.addListener(reply=>received.push(reply));
  port.postMessage({states:[]});await tick();
  assert.equal(requests[0].url,'http://127.0.0.1:48157/state');
  assert.equal(requests[0].options.redirect,'error');assert.equal(requests[0].options.credentials,'omit');
  assert.equal(requests[0].options.headers.Authorization,'Bearer '+config.token);
  assert.deepEqual(JSON.parse(requests[0].options.body),{session:'session-id',message:{states:[]}});
  assert.equal(received[0].accepted,true);
});
test('missing or malformed pairing data never sends a network request',async()=>{
  for(const config of [undefined,{port:0,token:'a'.repeat(64)},{port:'evil.example',token:'a'.repeat(64)},{port:48157,token:'bad'}]) {
    let requests=0,disconnected=0;
    const port=connection(config,async()=>{requests++;});
    port.onDisconnect.addListener(()=>disconnected++);
    port.postMessage({states:[]});await tick();
    assert.equal(requests,0);assert.equal(disconnected,1);
  }
});
test('bridge failure clears the temporary connection and suppresses late replies',async()=>{
  let disconnects=0,replies=0;
  const port=connection({port:48157,token:'a'.repeat(64)},async()=>({ok:false}));
  port.onDisconnect.addListener(()=>disconnects++);port.onMessage.addListener(()=>replies++);
  port.postMessage({states:[]});await tick();port.postMessage({states:[]});await tick();
  assert.equal(disconnects,1);assert.equal(replies,0);
});
function pairing(responses) {
  const stored=[], listeners=[], requests=[];
  const context={browser:{runtime:{id:'ext',onMessage:{addListener:fn=>listeners.push(fn)}},storage:{local:{set:async value=>stored.push(value)}}},
    fetch:async(url,options)=>{requests.push({url,options});const next=responses.shift();return {status:next[0],json:async()=>next[1]};},
    AbortSignal:{timeout:()=> 'timeout'},setTimeout:fn=>{fn();return 0;}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../safari-temporary/safari-pairing.js'),'utf8'),context);
  return {context,stored,listeners,requests};
}
test('automatic pairing waits for approval and stores the returned token',async()=>{
  const token='b'.repeat(64);
  const {context,stored,requests}=pairing([[202,{status:'pending'}],[202,{status:'pending'}],[200,{status:'approved',port:48157,token}]]);
  const result=await context.MeetingBusySafariPairing.pair();
  assert.equal(result.state,'approved');assert.equal(JSON.stringify(stored),JSON.stringify([{meetingBusyBridge:{port:48157,token}}]));
  assert.equal(requests.length,3);assert.equal(requests[0].url,'http://127.0.0.1:48157/pair');
  assert.equal(requests[0].options.redirect,'error');assert.equal(requests[0].options.credentials,'omit');
});
test('declined, malformed and failed pairing never store a token',async()=>{
  for(const [responses,expected] of [[[[403,{status:'denied'}]],'denied'],[[[200,{status:'approved',port:0,token:'x'}]],'failed'],[[[500,{}]],'failed']]) {
    const {context,stored}=pairing(responses);
    assert.equal((await context.MeetingBusySafariPairing.pair()).state,expected);assert.equal(stored.length,0);
  }
});
test('pairing messages are accepted only from the extension itself',()=>{
  const {listeners}=pairing([]);
  assert.equal(listeners[0]({type:'pair-status'},{id:'other'},()=>{throw new Error('replied');}),false);
  assert.equal(listeners[0]({type:'pair-status'},{id:'ext',tab:{id:1}},()=>{throw new Error('replied');}),false);
});
