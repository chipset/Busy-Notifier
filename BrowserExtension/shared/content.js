(() => {
  "use strict";
  if (globalThis.__meetingBusyMonitor) { globalThis.__meetingBusyMonitor.reconnect(); return; }
  const api = globalThis.browser || chrome;
  const detector = globalThis.MeetingBusyDetector;
  const service = detector.serviceForURL(location.href);
  if (!service) return;
  let port, observer, timer, permitted = false, scheduled = false, previous = "", stopped = false;
  function publish(state) {
    const signature = JSON.stringify(state);
    if (!port || signature === previous) return;
    previous = signature;
    try { port.postMessage({type: "state", service, ...state}); } catch (_) { previous = ""; }
  }
  function scan() {
    if (!permitted) return;
    const controls = [];
    for (const element of document.querySelectorAll('button,[role="button"],[role="menuitem"]')) {
      if (element.disabled || element.getAttribute("aria-disabled") === "true" || element.closest('[inert],[aria-hidden="true"]')) continue;
      // Background documents retain layout. Display:none post-call components have no rectangles.
      if (!element.getClientRects().length) continue;
      for (const label of [element.getAttribute("aria-label"), element.getAttribute("title"), element.textContent]) {
        if (label && label.length < 250) controls.push({label});
      }
    }
    publish(detector.classify(service, controls));
  }
  function schedule() {
    if (scheduled || !permitted) return;
    scheduled = true;
    queueMicrotask(() => { scheduled = false; scan(); });
  }
  function setPolicy(policy) {
    const enabled = Boolean(policy && policy.enabled && !policy.paused && Array.isArray(policy.services) && policy.services.includes(service));
    if (enabled === permitted) { if (enabled) scan(); return; }
    permitted = enabled;
    observer?.disconnect(); clearInterval(timer);
    if (!enabled) { previous = ""; publish({inMeeting: false, presenting: false}); return; }
    observer = new MutationObserver(schedule);
    observer.observe(document.documentElement, {subtree: true, childList: true, characterData: true, attributes: true,
      attributeFilter: ["aria-label", "aria-disabled", "aria-pressed", "title", "hidden", "disabled"]});
    timer = setInterval(scan, 2000);
    previous = ""; scan();
  }
  function connect() {
    if (stopped || port) { scan(); return; }
    try {
      port = api.runtime.connect({name: "meeting-busy-tab"});
      port.onMessage.addListener(message => { if (message.type === "policy") setPolicy(message.policy); });
      port.onDisconnect.addListener(() => {
        void api.runtime.lastError;
        port = null; previous = ""; setPolicy(null);
        if (!stopped) setTimeout(connect, 2000);
      });
      previous = "";
      port.postMessage({type: "hello", service});
    } catch (_) { port = null; if (!stopped) setTimeout(connect, 5000); }
  }
  globalThis.__meetingBusyMonitor = {reconnect: connect};
  addEventListener("pagehide", () => { stopped = true; setPolicy(null); port?.disconnect(); port = null; });
  addEventListener("pageshow", () => { stopped = false; connect(); });
  connect();
})();
