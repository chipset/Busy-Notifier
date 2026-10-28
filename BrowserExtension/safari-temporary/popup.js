"use strict";
const api = globalThis.browser || chrome;
async function refresh(type = "status") {
  try {
    const result = await api.runtime.sendMessage({type});
    document.getElementById("status").textContent = result.status;
    document.getElementById("active").textContent = `${result.active} active meeting frame${result.active === 1 ? "" : "s"}`;
  } catch (_) { document.getElementById("status").textContent = "Extension is restarting. Open this popup again."; }
}
document.getElementById("reconnect").addEventListener("click", () => refresh("reconnect"));
void refresh();
setInterval(() => refresh(), 1000);

document.getElementById("pair").addEventListener("submit", async event => {
  event.preventDefault();
  const field = document.getElementById("code"), result = document.getElementById("pair-result");
  const match = /^(\d{1,5}):([a-f0-9]{64})$/i.exec(field.value.trim());
  if (!match || Number(match[1]) < 1 || Number(match[1]) > 65535) { result.textContent = "Copy a fresh pairing code from the Mac app."; return; }
  await api.storage.local.set({meetingBusyBridge: {port: Number(match[1]), token: match[2]}});
  field.value = ""; result.textContent = "Code saved. Connecting…";
  await refresh("reconnect");
});
