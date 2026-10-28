#!/usr/bin/env python3
"""Run the actual Safari native handler in an ad hoc sandboxed test app."""
import http.server
import json
import pathlib
import plistlib
import secrets
import subprocess
import tempfile
import threading

root = pathlib.Path(__file__).resolve().parent.parent
(root / '.build').mkdir(exist_ok=True)
secret = secrets.token_hex(32)
mode = 'success'
received = []
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_POST(self):
        assert self.path == '/state'
        assert self.headers['Authorization'] == 'Bearer ' + secret
        envelope = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert set(envelope) == {'session', 'message'}
        assert envelope['message']['states'][0]['service'] == 'Google Meet'
        received.append(envelope)
        if mode == 'redirect':
            self.send_response(302); self.send_header('Location', 'http://127.0.0.1:1/'); self.end_headers(); return
        data = json.dumps({'protocolVersion':1,'accepted':True,'policy':{'enabled':True,'paused':False,'services':['Google Meet']}}).encode()
        self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
server = http.server.ThreadingHTTPServer(('127.0.0.1',0), Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='safari-handler-',dir=root / '.build') as temp:
        base = pathlib.Path(temp)
        app = base / 'HandlerTest.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        config = {'port':server.server_port,'token':secret}
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.meetingbusy.handlertest','CFBundleExecutable':'HandlerTest','CFBundlePackageType':'APPL','MeetingBusySafariBridge':config,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}))
        source = base / 'main.swift'
        source.write_text('''import Foundation
import SafariServices
let done = DispatchSemaphore(value: 0)
let expectSuccess = CommandLine.arguments.last == "success"
final class TestContext: NSExtensionContext {
    override var inputItems: [Any] {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: ["session": UUID().uuidString,
            "message": ["protocolVersion": 1, "states": [["id": "1:0", "service": "Google Meet", "inMeeting": true, "presenting": false]]]]]
        return [item]
    }
    override func completeRequest(returningItems items: [Any]?, completionHandler: ((Bool) -> Void)? = nil) {
        guard expectSuccess, let item = items?.first as? NSExtensionItem,
              let reply = item.userInfo?[SFExtensionMessageKey] as? [String: Any], reply["accepted"] as? Bool == true else { exit(2) }
        done.signal()
    }
    override func cancelRequest(withError error: Error) {
        if expectSuccess { print("Native handler request failed: \\(error.localizedDescription)"); exit(3) }
        done.signal()
    }
}
let handler = SafariWebExtensionHandler()
let context = TestContext()
handler.beginRequest(with: context)
if done.wait(timeout: .now() + 10) == .timedOut { exit(4) }
''')
        binary = app / 'Contents/MacOS/HandlerTest'
        subprocess.run(['xcrun','swiftc','-swift-version','5',str(root / 'BrowserExtension/safari/SafariWebExtensionHandler.swift'),str(source),'-framework','SafariServices','-o',str(binary)],check=True)
        entitlements = base / 'entitlements.plist'
        entitlements.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True}))
        subprocess.run(['codesign','--force','--sign','-','--entitlements',str(entitlements),str(app)],check=True,stdout=subprocess.DEVNULL)
        subprocess.run([str(binary),'success'],check=True,timeout=15)
        mode = 'redirect'
        subprocess.run([str(binary),'failure'],check=True,timeout=15)
        assert len(received) == 2
        print('PASS: actual sandboxed Safari handler forwards authenticated state, returns policy, and refuses redirects')
finally:
    server.shutdown()
    server.server_close()
