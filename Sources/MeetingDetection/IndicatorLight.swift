import Foundation
import Darwin

/// What the optional USB light should show. The light never receives meeting details.
public enum LightState: String, CaseIterable, Sendable {
    case busy, presenting, free, attention, off
}

public enum IndicatorLight {
    public static let helloReply = "MEETINGBUSY 1"
    public static let hello = Data("HELLO\n".utf8)
    /// The firmware turns the light off if it hears nothing for 10 seconds, so resend more often than that.
    public static let heartbeat: TimeInterval = 3

    public static func state(for reason: IndicatorReason, extensionLost: Bool = false) -> LightState {
        switch reason {
        case .forcedBusy, .meeting, .preview: .busy
        case .presenting: .presenting
        case .setupNeeded: .attention
        case .idle: extensionLost ? .attention : .free
        case .available: .free
        case .paused, .disabled: .off
        }
    }

    public static func command(_ state: LightState) -> Data { Data("STATE \(state.rawValue)\n".utf8) }
}

/// A blocking, non-canonical serial connection used only for the small line protocol above.
/// All access must come from one queue.
public final class SerialLink: @unchecked Sendable {
    public let path: String
    private var descriptor: Int32

    public init?(path: String) {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else { Darwin.close(fd); return nil }
        cfmakeraw(&settings)
        cfsetspeed(&settings, speed_t(B115200))
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(fd, TCSANOW, &settings) == 0 else { Darwin.close(fd); return nil }
        tcflush(fd, TCIOFLUSH)
        self.path = path; descriptor = fd
    }

    public static func candidatePaths() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []).filter { $0.hasPrefix("cu.usbmodem") }.sorted().map { "/dev/\($0)" }
    }

    /// Opens the first port whose firmware answers the hello handshake.
    public static func connect(paths: [String] = candidatePaths(), timeout: TimeInterval = 0.8) -> SerialLink? {
        for path in paths {
            guard let link = SerialLink(path: path) else { continue }
            if link.handshake(timeout: timeout) { return link }
            link.close()
        }
        return nil
    }

    public func handshake(timeout: TimeInterval) -> Bool {
        guard write(IndicatorLight.hello) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = readLine(timeout: max(0.05, deadline.timeIntervalSinceNow)), line == IndicatorLight.helloReply { return true }
        }
        return false
    }

    @discardableResult public func write(_ data: Data, timeout: TimeInterval = 0.5) -> Bool {
        guard descriptor >= 0 else { return false }
        var offset = 0
        let deadline = Date().addingTimeInterval(timeout)
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 { offset += written; continue }
            guard written < 0, errno == EAGAIN || errno == EINTR, Date() < deadline else { return false }
            var pending = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            _ = poll(&pending, 1, 50)
        }
        return true
    }

    public func readLine(timeout: TimeInterval) -> String? {
        guard descriptor >= 0 else { return nil }
        var line = [UInt8]()
        let deadline = Date().addingTimeInterval(timeout)
        while line.count < 256 {
            var pending = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
            guard poll(&pending, 1, remaining) > 0 else { return nil }
            var byte: UInt8 = 0
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 0 { return nil }
            if count < 0 { if errno == EAGAIN || errno == EINTR { continue }; return nil }
            if byte == 10 { return String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
            line.append(byte)
        }
        return nil
    }

    public func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor); descriptor = -1
    }
    deinit { close() }
}
