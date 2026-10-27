(function (root) {
  "use strict";
  const services = new Set(["Google Meet", "Microsoft Teams", "Webex", "Zoom"]);
  const matches = (label, phrases) => phrases.some(phrase => label === phrase || [",", ".", " (", "\n", "\t"].some(suffix => label.startsWith(phrase + suffix)));
  function serviceForURL(value) {
    try {
      const url = new URL(value);
      if (url.protocol !== "https:") return null;
      const host = url.hostname.toLowerCase();
      if (host === "meet.google.com" && url.pathname !== "/" && url.pathname !== "") return "Google Meet";
      if (["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"].includes(host)) return "Microsoft Teams";
      if (host === "webex.com" || host.endsWith(".webex.com")) return "Webex";
      if (["zoom.us", "zoom.com"].some(domain => host === domain || host.endsWith("." + domain))) return "Zoom";
    } catch (_) { /* Unrecognized origins never supply meeting evidence. */ }
    return null;
  }
  function classify(service, controls) {
    if (!services.has(service)) return {inMeeting: false, presenting: false};
    const labels = controls.filter(control => control.actionable !== false).map(control => String(control.label).trim().toLowerCase());
    const any = phrases => labels.some(label => matches(label, phrases));
    const ended = any(["rejoin", "return to home", "back to home", "join a meeting", "new meeting"]);
    if (ended) return {inMeeting: false, presenting: false};
    const presenting = any(["stop sharing", "stop share", "stop presenting", "stop screen sharing"]);
    const endPhrases = service === "Google Meet" ? ["leave call", "leave meeting", "hang up"]
      : ["leave call", "leave meeting", "end call", "end meeting", "end meeting for all", "hang up", "leave webinar", "end webinar", "leave or end meeting"];
    const ambiguousEnd = ["Zoom", "Microsoft Teams"].includes(service) && any(["leave", "end"])
      && any(["mute", "unmute", "mute audio", "unmute audio", "start video", "stop video", "turn camera on", "turn camera off", "join audio", "camera", "microphone", "mic", "audio", "video"]);
    return {inMeeting: presenting || any(endPhrases) || ambiguousEnd, presenting};
  }
  function validState(value) {
    return value && services.has(value.service) && typeof value.inMeeting === "boolean" && typeof value.presenting === "boolean"
      && (!value.presenting || value.inMeeting);
  }
  const api = {serviceForURL, classify, validState};
  root.MeetingBusyDetector = api;
  if (typeof module !== "undefined") module.exports = api;
})(globalThis);
