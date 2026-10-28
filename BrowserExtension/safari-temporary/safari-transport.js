"use strict";
// Temporary Safari extensions cannot call an embedded native handler.
// Pair explicitly with the local app and send state only to IPv4 loopback.
globalThis.MeetingBusySafariTransport = {
  connect() {
    const api = globalThis.browser || chrome;
    const session = crypto.randomUUID();
    const event = () => { const listeners = []; return {addListener(fn) { listeners.push(fn); }, emit(value) { for (const fn of listeners) fn(value); }}; };
    const onMessage = event(), onDisconnect = event();
    let stopped = false, busy = false, pending;
    const port = {onMessage, onDisconnect,
      disconnect() { stopped = true; pending = undefined; },
      postMessage(message) { if (!stopped) { pending = message; void flush(); } }
    };
    async function flush() {
      if (busy || stopped || !pending) return;
      busy = true;
      const message = pending; pending = undefined;
      try {
        const {meetingBusyBridge: config} = await api.storage.local.get("meetingBusyBridge");
        if (!config || !Number.isInteger(config.port) || config.port < 1 || config.port > 65535 || !/^[a-f0-9]{64}$/i.test(config.token)) throw new Error("Pair in the popup first");
        const response = await fetch(`http://127.0.0.1:${config.port}/state`, {
          method: "POST", headers: {"Authorization": `Bearer ${config.token}`, "Content-Type": "application/json"},
          body: JSON.stringify({session, message}), redirect: "error", credentials: "omit", cache: "no-store",
          signal: AbortSignal.timeout(3000)
        });
        if (!response.ok) throw new Error("Local bridge unavailable");
        const reply = await response.json();
        if (!stopped) onMessage.emit(reply);
      } catch (_) {
        if (!stopped) { stopped = true; pending = undefined; onDisconnect.emit(); }
      } finally { busy = false; if (!stopped && pending) void flush(); }
    }
    return port;
  }
};
