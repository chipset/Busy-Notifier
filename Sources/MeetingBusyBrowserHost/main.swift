import Foundation
import MeetingDetection

// The host gets no window, URL, title, or meeting text. Only typed, validated state is saved.
let directory = ProcessInfo.processInfo.environment["MEETING_BUSY_BRIDGE_TEST_DIRECTORY"].map { URL(fileURLWithPath: $0) } ?? BrowserBridgeStore.defaultDirectory
let store = BrowserBridgeStore(directory: directory)
let session = UUID()
defer { store.removeSnapshot(session: session) }
do {
    try NativeMessageIO.write(JSONEncoder().encode(BrowserBridgeReply(accepted: true, policy: store.readPolicy())), to: .standardOutput)
    while let data = try NativeMessageIO.read(from: .standardInput) {
        let policy = store.readPolicy()
        guard let message = try? JSONDecoder().decode(BrowserBridgeMessage.self, from: data), message.isValid else {
            store.removeSnapshot(session: session)
            try NativeMessageIO.write(JSONEncoder().encode(BrowserBridgeReply(accepted: false, policy: policy)), to: .standardOutput)
            continue
        }
        if policy.enabled && !policy.paused {
            try store.writeSnapshot(BrowserBridgeSnapshot(states: message.states.filter { policy.allows($0.service) }), session: session)
        } else { store.removeSnapshot(session: session) }
        try NativeMessageIO.write(JSONEncoder().encode(BrowserBridgeReply(accepted: true, policy: policy)), to: .standardOutput)
    }
} catch {
    store.removeSnapshot(session: session)
    FileHandle.standardError.write(Data("Meeting Busy browser bridge: invalid message or unavailable local storage.\n".utf8))
    exit(1)
}
