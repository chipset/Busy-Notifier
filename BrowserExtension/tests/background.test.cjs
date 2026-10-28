const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const detector = require('../shared/detector.js');
function event() { const listeners=[]; return {addListener(fn){listeners.push(fn);},emit(...args){for(const fn of listeners)fn(...args);}}; }
function port(sender={}) { return {sender,name:'meeting-busy-tab',onMessage:event(),onDisconnect:event(),sent:[],disconnected:false,
  postMessage(data){this.sent.push(data);},disconnect(){this.disconnected=true;this.onDisconnect.emit();}}; }
function worker() {
  const native=port(), runtime={id:'test-extension',onConnect:event(),onMessage:event(),onInstalled:event(),onStartup:event(),
    connectNative(){return native;},getManifest(){return {host_permissions:[]};}};
  const tabs={onRemoved:event(),onUpdated:event(),query:async()=>[]};
  const intervals=[];
  const context={chrome:{runtime,tabs,scripting:{executeScript:async()=>{}}},MeetingBusyDetector:detector,importScripts(){},
    setInterval(fn){intervals.push(fn);},setTimeout(){},clearTimeout(){},console};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../shared/background.js'),'utf8'),context);
  const policy={enabled:true,paused:false,services:['Google Meet','Zoom']};
  native.onMessage.emit({protocolVersion:1,accepted:true,policy});
  function connect(tab=1,frame=0,url='https://meet.google.com/abc-defg-hij',id=runtime.id){const p=port({id,tab:{id:tab,url},url,frameId:frame});runtime.onConnect.emit(p);return p;}
  return {native,runtime,tabs,intervals,policy,connect,last(){return JSON.parse(JSON.stringify(native.sent.at(-1)));}};
}
test('inactive tab evidence persists through worker heartbeats',()=>{
  const w=worker(),p=w.connect();
  p.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  w.intervals[0]();
  assert.deepEqual(w.last().states,[{id:'1:0',service:'Google Meet',inMeeting:true,presenting:false}]);
});
test('closing or navigating a tab clears its state',()=>{
  const w=worker(),p=w.connect();
  p.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  w.tabs.onUpdated.emit(1,{status:'loading'});
  assert.equal(w.last().states.length,0);
  p.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  assert.equal(w.last().states.length,0);
  const second=w.connect(2);
  second.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  w.tabs.onRemoved.emit(2);
  assert.equal(w.last().states.length,0);
});
test('pausing and service switches stop cached positives and require a fresh state',()=>{
  const w=worker(),p=w.connect();
  p.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:true});
  w.native.onMessage.emit({protocolVersion:1,accepted:true,policy:{...w.policy,paused:true}});
  w.intervals[0]();assert.equal(w.last().states[0].inMeeting,false);
  w.native.onMessage.emit({protocolVersion:1,accepted:true,policy:w.policy});
  w.intervals[0]();assert.equal(w.last().states[0].inMeeting,false);
  p.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  assert.equal(w.last().states[0].inMeeting,true);
  w.native.onMessage.emit({protocolVersion:1,accepted:true,policy:{...w.policy,services:['Zoom']}});
  w.intervals[0]();assert.equal(w.last().states[0].inMeeting,false);
});
test('untrusted extensions, origins, and mismatched service messages are ignored',()=>{
  const w=worker();
  assert.equal(w.connect(1,0,'https://meet.google.com.evil.example/a').disconnected,true);
  assert.equal(w.connect(1,0,'https://meet.google.com/a','other-extension').disconnected,true);
  const p=w.connect();
  p.onMessage.emit({type:'state',service:'Zoom',inMeeting:true,presenting:false});
  w.intervals[0]();assert.equal(w.last().states[0].inMeeting,false);
});
test('disconnecting an old document cannot erase the replacement',()=>{
  const w=worker(),old=w.connect(),replacement=w.connect();
  replacement.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  old.onDisconnect.emit();w.intervals[0]();
  assert.equal(w.last().states[0].inMeeting,true);
  replacement.onDisconnect.emit();assert.equal(w.last().states.length,0);
});
test('native disconnection clears policy and stops reports',()=>{
  const w=worker(),p=w.connect();
  p.onMessage.emit({type:'state',service:'Google Meet',inMeeting:true,presenting:false});
  w.native.onDisconnect.emit();
  assert.equal(p.sent.at(-1).policy.enabled,false);
});
test('Safari Manifest V2 connects existing meeting tabs using its supported injection API',async()=>{
  const native=port(), injected=[], hosts=['https://meet.google.com/*'];
  const runtime={id:'safari',onConnect:event(),onMessage:event(),onInstalled:event(),onStartup:event(),
    getManifest(){return {manifest_version:2,permissions:['nativeMessaging',...hosts]};}};
  const tabs={onRemoved:event(),onUpdated:event(),query:async options=>{
    assert.deepEqual(Array.from(options.url),hosts); return [{id:4}];
  },executeScript:async(id,options)=>{injected.push({id,...options});}};
  const context={browser:{runtime,tabs},MeetingBusyDetector:detector,
    MeetingBusySafariTransport:{connect:()=>native},setInterval(){},setTimeout(){},clearTimeout(){}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../shared/background.js'),'utf8'),context);
  await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(injected,[{id:4,file:'detector.js',allFrames:true},{id:4,file:'content.js',allFrames:true}]);
});
