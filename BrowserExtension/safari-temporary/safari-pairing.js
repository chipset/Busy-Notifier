"use strict";
// Asks the Mac app to approve this extension. The app shows an Allow prompt and, once the
// user agrees, returns a per-install token. It runs in the persistent background page so a
// closing popup (Safari dismisses it when the Mac app prompt takes focus) cannot cancel it.
(() => {
  const api = globalThis.browser || chrome;
  const port = 48157, attempts = 30, delay = 2000;
  let state = {state: "idle", message: ""}, running = false;
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function request() {
    const response = await fetch(`http://127.0.0.1:${port}/pair`, {
      method: "POST", redirect: "error", credentials: "omit", cache: "no-store", signal: AbortSignal.timeout(3000)
    });
    let body = {};
    try { body = await response.json(); } catch (_) {}
    return {status: response.status, body};
  }
  async function pair() {
    if (running) return state;
    running = true;
    state = {state: "waiting", message: "Click Allow in the Meeting Busy window on your Mac."};
    try {
      for (let attempt = 0; attempt < attempts; attempt++) {
        const {status, body} = await request();
        if (status === 200 && body.status === "approved" && Number.isInteger(body.port) && body.port >= 1 && body.port <= 65535 && /^[a-f0-9]{64}$/i.test(body.token || "")) {
          await api.storage.local.set({meetingBusyBridge: {port: body.port, token: body.token}});
          state = {state: "approved", message: "Paired with Meeting Busy. Connecting…"};
          return state;
        }
        if (status === 403) { state = {state: "denied", message: "The request was declined or too many were made. Try again in a few minutes."}; return state; }
        if (status !== 202) throw new Error("Unexpected reply");
        await sleep(delay);
      }
      state = {state: "failed", message: "Timed out waiting for approval. Choose Pair automatically to try again."};
    } catch (_) {
      state = {state: "failed", message: "Could not reach Meeting Busy. Open the app and turn on browser integration."};
    } finally { running = false; }
    return state;
  }
  globalThis.MeetingBusySafariPairing = {pair, status: () => state};
  api.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (sender.id !== api.runtime.id || sender.tab) return false;
    if (message.type === "pair") { void pair(); sendResponse(state); }
    if (message.type === "pair-status") sendResponse(state);
    return false;
  });
})();
