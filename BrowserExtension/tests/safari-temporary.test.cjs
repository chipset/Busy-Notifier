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
