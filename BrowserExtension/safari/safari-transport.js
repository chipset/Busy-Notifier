"use strict";
// Safari native messages are request/reply operations handled by the embedded
// app extension. Adapt them to the existing background worker's port interface.
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
        const reply = await api.runtime.sendNativeMessage("local.meetingbusy", {session, message});
        if (!stopped) onMessage.emit(reply);
      } catch (_) {
        if (!stopped) { stopped = true; pending = undefined; onDisconnect.emit(); }
      } finally { busy = false; if (!stopped && pending) void flush(); }
    }
    return port;
  }
};
