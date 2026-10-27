"use strict";
if (typeof importScripts === "function") importScripts("detector.js");
const api = globalThis.browser || chrome;
const detector = globalThis.MeetingBusyDetector;
const nativeHost = "local.meetingbusy.browser";
const documents = new Map();
let nativePort, reconnectTimer, policy = {enabled: false, paused: false, services: []};
let bridgeStatus = "Open Meeting Busy Settings and install the browser bridge.";
function permitted(service) { return policy.enabled && !policy.paused && policy.services.includes(service); }
function broadcastPolicy() {
  for (const document of documents.values()) {
    if (!permitted(document.service)) document.state = {inMeeting: false, presenting: false};
    try { document.port.postMessage({type: "policy", policy}); } catch (_) {}
  }
}
function snapshot() {
  return {protocolVersion: 1, states: [...documents.entries()].slice(0, 256).map(([id, document]) => ({id, service: document.service,
    inMeeting: permitted(document.service) && document.state.inMeeting,
    presenting: permitted(document.service) && document.state.presenting}))};
}
function sendSnapshot() {
  if (!nativePort) { connectNative(); return; }
  try { nativePort.postMessage(snapshot()); } catch (_) { disconnectNative(); }
}
function disconnectNative() {
  const previous = nativePort;
  nativePort = null;
  try { previous?.disconnect(); } catch (_) {}
  policy = {enabled: false, paused: false, services: []};
  bridgeStatus = "Bridge disconnected. Open Meeting Busy and check its browser setup.";
  broadcastPolicy();
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(connectNative, 5000);
}
function connectNative() {
  if (nativePort) return;
  clearTimeout(reconnectTimer);
  try {
    const port = api.runtime.connectNative(nativeHost);
    nativePort = port;
    port.onMessage.addListener(reply => {
      if (nativePort !== port) return;
      if (reply.protocolVersion !== 1 || typeof reply.accepted !== "boolean" || !reply.policy || !Array.isArray(reply.policy.services)) return;
      policy = {enabled: reply.policy.enabled === true, paused: reply.policy.paused === true,
        services: reply.policy.services.filter(service => ["Google Meet", "Microsoft Teams", "Webex", "Zoom"].includes(service))};
      bridgeStatus = !reply.accepted ? "The app rejected a state message. Reconnect or update the extension."
        : (!policy.enabled ? "Browser integration is off in the app." : (policy.paused ? "Detection is paused in the app." : "Connected to Meeting Busy."));
      broadcastPolicy();
    });
    port.onDisconnect.addListener(() => { if (nativePort !== port) return; void api.runtime.lastError; disconnectNative(); });
    sendSnapshot();
  } catch (_) { disconnectNative(); }
}
api.runtime.onConnect.addListener(port => {
  if (port.name !== "meeting-busy-tab" || port.sender?.id !== api.runtime.id || !Number.isInteger(port.sender?.tab?.id)) { port.disconnect(); return; }
  const service = detector.serviceForURL(port.sender.url || port.sender.tab.url);
  if (!service) { port.disconnect(); return; }
  const id = `${port.sender.tab.id}:${port.sender.frameId || 0}`;
  const document = {port, service, state: {inMeeting: false, presenting: false}};
  documents.set(id, document);
  port.onMessage.addListener(message => {
    if (documents.get(id) !== document || message.service !== service) return;
    if (message.type === "state" && detector.validState(message) && permitted(service)) {
      document.state = {inMeeting: message.inMeeting, presenting: message.presenting};
      sendSnapshot();
    }
    if (message.type === "hello") port.postMessage({type: "policy", policy});
  });
  port.onDisconnect.addListener(() => { if (documents.get(id) === document) { documents.delete(id); sendSnapshot(); } });
  port.postMessage({type: "policy", policy});
  connectNative();
});
api.tabs.onRemoved.addListener(tabID => {
  for (const id of documents.keys()) if (id.startsWith(`${tabID}:`)) documents.delete(id);
  sendSnapshot();
});
api.tabs.onUpdated.addListener((tabID, change) => {
  if (change.status !== "loading") return;
  for (const id of documents.keys()) if (id.startsWith(`${tabID}:`)) documents.delete(id);
  sendSnapshot();
});
async function connectOpenTabs() {
  const manifest = api.runtime.getManifest();
  const tabs = await api.tabs.query({url: manifest.host_permissions});
  for (const tab of tabs) {
    try { await api.scripting.executeScript({target: {tabId: tab.id, allFrames: true}, files: ["detector.js", "content.js"]}); } catch (_) {}
  }
}
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender.id !== api.runtime.id || sender.tab) return false;
  if (message.type === "reconnect") { connectNative(); void connectOpenTabs(); }
  if (["status", "reconnect"].includes(message.type)) {
    sendResponse({status: bridgeStatus, connected: Boolean(nativePort), active: [...documents.values()].filter(document => document.state.inMeeting && permitted(document.service)).length});
  }
  return false;
});
api.runtime.onInstalled.addListener(() => { connectNative(); void connectOpenTabs(); });
api.runtime.onStartup.addListener(() => { connectNative(); void connectOpenTabs(); });
// A connected native port keeps Chromium's worker alive. Heartbeats originate here,
// independently of hidden-tab timer throttling. Mutation events supply tab transitions.
setInterval(sendSnapshot, 5000);
connectNative();
void connectOpenTabs();
