const test = require('node:test');
const assert = require('node:assert/strict');
const detector = require('../shared/detector.js');
const controls = labels => labels.map(label => ({label}));
test('provider origins are exact HTTPS origins', () => {
  assert.equal(detector.serviceForURL('https://meet.google.com/abc-defg-hij'), 'Google Meet');
  assert.equal(detector.serviceForURL('https://company.webex.com/meet/person'), 'Webex');
  assert.equal(detector.serviceForURL('https://teams.cloud.microsoft/v2'), 'Microsoft Teams');
  assert.equal(detector.serviceForURL('https://app.zoom.us/wc/123'), 'Zoom');
  for (const url of ['https://meet.google.com/', 'http://meet.google.com/abc', 'https://meet.google.com.evil.example/abc', 'https://notwebex.com/', 'https://example.com/?url=https://app.zoom.us']) assert.equal(detector.serviceForURL(url), null);
});
test('prejoin and left-call screens are idle for all providers', () => {
  for (const service of ['Google Meet', 'Microsoft Teams', 'Zoom', 'Webex']) {
    assert.equal(detector.classify(service, controls(['Join now', 'Microphone'])).inMeeting, false);
    assert.equal(detector.classify(service, controls(['Rejoin', 'Leave meeting'])).inMeeting, false);
  }
});
test('call controls detect muted and camera-off meetings', () => {
  for (const service of ['Microsoft Teams', 'Zoom']) assert.equal(detector.classify(service, controls(['Leave', 'Unmute', 'Start video'])).inMeeting, true);
  assert.equal(detector.classify('Google Meet', controls(['Leave call (⌘W)'])).inMeeting, true);
  assert.equal(detector.classify('Webex', controls(['Leave or end meeting'])).inMeeting, true);
});
test('only the users own stop-sharing control marks presenting', () => {
  assert.deepEqual(detector.classify('Google Meet', controls(['Leave call', 'Stop presenting'])), {inMeeting:true, presenting:true});
  assert.deepEqual(detector.classify('Zoom', controls(['Leave meeting', 'Alice is sharing'])), {inMeeting:true, presenting:false});
  assert.equal(detector.classify('Google Meet', [{label:'Leave call',actionable:false}]).inMeeting, false);
});
test('similar labels and arbitrary message shapes are rejected', () => {
  assert.equal(detector.classify('Microsoft Teams', controls(['Leave feedback', 'Leave team'])).inMeeting, false);
  assert.equal(detector.classify('Zoom', controls(['Leave'])).inMeeting, false);
  assert.equal(detector.validState({service:'Zoom',inMeeting:false,presenting:true}), false);
  assert.equal(detector.validState({service:'Unknown',inMeeting:true,presenting:false}), false);
  assert.equal(detector.validState({service:'Zoom',inMeeting:true,presenting:false}), true);
});
test('Spanish, French and German controls detect calls and own sharing', () => {
  for (const [leave, stop] of [
    ['Salir de la llamada', 'Dejar de compartir'],
    ["Quitter l'appel", 'Arrêter le partage'],
    ['Besprechung verlassen', 'Freigabe beenden']
  ]) {
    assert.deepEqual(detector.classify('Google Meet', controls([leave, stop])), {inMeeting:true, presenting:true});
    assert.equal(detector.classify('Google Meet', controls([leave])).inMeeting, true);
  }
  assert.equal(detector.classify('Zoom', controls(['Alice is sharing'])).presenting, false);
});
test('mid-call "New meeting" and "Join a meeting" buttons do not end Teams or Meet calls', () => {
  assert.equal(detector.classify('Microsoft Teams', controls(['Leave', 'Unmute', 'New meeting'])).inMeeting, true);
  assert.equal(detector.classify('Google Meet', controls(['Leave call', 'Join a meeting'])).inMeeting, true);
  assert.equal(detector.classify('Zoom', controls(['Leave meeting', 'New meeting'])).inMeeting, false);
});
test('Webex combined leave/end labels are detected', () => {
  for (const label of ['Leave / end meeting', 'End or leave meeting']) assert.equal(detector.classify('Webex', controls([label])).inMeeting, true);
});
