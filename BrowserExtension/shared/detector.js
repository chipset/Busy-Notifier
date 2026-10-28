(function (root) {
  "use strict";
  const services = new Set(["Google Meet", "Microsoft Teams", "Webex", "Zoom"]);
  const localizedLeave = ["salir de la llamada", "salir de la reunión", "abandonar la reunión", "quitter l’appel", "quitter l'appel", "quitter la réunion", "anruf verlassen", "besprechung verlassen", "meeting verlassen"];
  const localizedStopSharing = ["dejar de compartir", "detener la presentación", "dejar de presentar", "arrêter le partage", "arrêter de partager", "arrêter la présentation", "freigabe beenden", "bildschirmfreigabe beenden", "präsentation beenden"];
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
  // Mirrors Sources/MeetingDetection/Detection.swift. tests/parity.test.cjs fails if they diverge.
  const rules = {
    end: {
      "Google Meet": ["leave call", "leave meeting", "hang up"],
      "Microsoft Teams": ["leave call", "leave meeting", "hang up", "end call", "end meeting"],
      "Webex": ["leave meeting", "end meeting", "leave call", "end call", "leave / end meeting", "leave or end meeting", "end or leave meeting"],
      "Zoom": ["leave meeting", "end meeting", "end meeting for all", "leave webinar", "end webinar"]
    },
    stopSharing: ["stop sharing", "stop presenting", "stop share", "stop screen sharing"],
    teamsLeaveCompanions: ["mute", "unmute", "turn camera on", "turn camera off", "camera", "mic", "microphone"],
    zoomLeaveCompanions: ["mute", "unmute", "mute audio", "unmute audio", "mute my audio", "unmute my audio", "start video", "stop video", "join audio", "audio", "video"],
    endedAny: ["rejoin", "return to home", "back to home"],
    endedZoom: ["join a meeting", "new meeting"],
    localizedLeave, localizedStopSharing
  };
  function classify(service, controls) {
    if (!services.has(service)) return {inMeeting: false, presenting: false};
    const labels = controls.filter(control => control.actionable !== false).map(control => String(control.label).trim().toLowerCase());
    const any = phrases => labels.some(label => matches(label, phrases));
    // "New meeting"/"Join a meeting" only mean a call ended in Zoom; other providers show them mid-call.
    if (any([...rules.endedAny, ...(service === "Zoom" ? rules.endedZoom : [])])) return {inMeeting: false, presenting: false};
    const presenting = any([...rules.stopSharing, ...localizedStopSharing]);
    // Teams and Zoom label the call button just "Leave"/"End"; require a companion audio/video control.
    const ambiguousEnd = (service === "Microsoft Teams" && any(["leave"]) && any(rules.teamsLeaveCompanions))
      || (service === "Zoom" && any(["end", "leave"]) && any(rules.zoomLeaveCompanions));
    return {inMeeting: presenting || any([...rules.end[service], ...localizedLeave]) || ambiguousEnd, presenting};
  }
  function validState(value) {
    return value && services.has(value.service) && typeof value.inMeeting === "boolean" && typeof value.presenting === "boolean"
      && (!value.presenting || value.inMeeting);
  }
  const api = {serviceForURL, classify, validState, rules};
  root.MeetingBusyDetector = api;
  if (typeof module !== "undefined") module.exports = api;
})(globalThis);
