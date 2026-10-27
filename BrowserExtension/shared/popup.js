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
