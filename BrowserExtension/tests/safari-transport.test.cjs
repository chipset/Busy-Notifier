const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const tick = () => new Promise(resolve => setImmediate(resolve));
function transport(sendNativeMessage) {
  const context = {browser:{runtime:{sendNativeMessage}}, crypto:{randomUUID:()=> 'session-id'}};
  vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../safari/safari-transport.js'),'utf8'), context);
  return context.MeetingBusySafariTransport.connect();
}
test('Safari native transport returns policy and coalesces overlapping snapshots', async () => {
  const sent = [], replies = [];
  let finish;
  const port = transport((host, envelope) => { sent.push({host,envelope}); return new Promise(resolve => finish=resolve); });
  port.onMessage.addListener(reply => replies.push(reply));
  port.postMessage({states:[1]}); port.postMessage({states:[2]}); port.postMessage({states:[]});
  assert.equal(sent.length,1);
  finish({accepted:true}); await tick();
  assert.equal(replies.length,1); assert.equal(sent.length,2);
  assert.equal(sent[1].host,'local.meetingbusy'); assert.equal(sent[1].envelope.session,'session-id');
  assert.deepEqual(sent[1].envelope.message.states,[]);
  port.disconnect(); finish({accepted:true}); await tick();
  assert.equal(replies.length,1);
});
test('Safari transport failure disconnects once and stops sending', async () => {
  let calls=0, disconnects=0;
  const port=transport(async()=>{ calls++; throw new Error('app not running'); });
  port.onDisconnect.addListener(()=>disconnects++);
  port.postMessage({states:[]}); await tick();
  port.postMessage({states:[]}); await tick();
  assert.equal(calls,1); assert.equal(disconnects,1);
});
