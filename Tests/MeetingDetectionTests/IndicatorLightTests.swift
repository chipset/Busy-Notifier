import XCTest
import Darwin
@testable import MeetingDetection

final class IndicatorLightTests: XCTestCase {
    func testReasonsMapToLightStates() {
        XCTAssertEqual(IndicatorLight.state(for: .meeting), .busy)
        XCTAssertEqual(IndicatorLight.state(for: .forcedBusy), .busy)
        XCTAssertEqual(IndicatorLight.state(for: .preview), .busy)
        XCTAssertEqual(IndicatorLight.state(for: .presenting), .presenting)
        XCTAssertEqual(IndicatorLight.state(for: .available), .free)
        XCTAssertEqual(IndicatorLight.state(for: .idle), .free)
        XCTAssertEqual(IndicatorLight.state(for: .idle, extensionLost: true), .attention)
        XCTAssertEqual(IndicatorLight.state(for: .setupNeeded), .attention)
        XCTAssertEqual(IndicatorLight.state(for: .paused), .off)
        XCTAssertEqual(IndicatorLight.state(for: .disabled), .off)
    }

    func testCommandsCarryOnlyTheStateName() {
        for state in LightState.allCases {
            XCTAssertEqual(String(decoding: IndicatorLight.command(state), as: UTF8.self), "STATE \(state.rawValue)\n")
        }
    }

    /// A pseudo-terminal stands in for the board: it answers HELLO and records the commands it receives.
    func testHandshakeAndCommandsOverASerialDevice() throws {
        var master: Int32 = -1, slave: Int32 = -1
        XCTAssertEqual(openpty(&master, &slave, nil, nil, nil), 0)
        defer { Darwin.close(master); Darwin.close(slave) }
        let path = String(cString: ttyname(slave))
        let received = LockedLines()
        let thread = Thread {
            var buffer = Data()
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                var pending = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
                guard poll(&pending, 1, 100) > 0 else { continue }
                var byte: UInt8 = 0
                guard Darwin.read(master, &byte, 1) == 1 else { return }
                if byte != 10 { buffer.append(byte); continue }
                let line = String(decoding: buffer, as: UTF8.self); buffer = Data()
                received.append(line)
                if line == "HELLO" { let reply = Array((IndicatorLight.helloReply + "\n").utf8); _ = Darwin.write(master, reply, reply.count) }
                if line == "STATE off" { return }
            }
        }
        thread.start()
        let link = try XCTUnwrap(SerialLink.connect(paths: [path], timeout: 2))
        XCTAssertTrue(link.write(IndicatorLight.command(.busy)))
        XCTAssertTrue(link.write(IndicatorLight.command(.off)))
        link.close()
        let deadline = Date().addingTimeInterval(3)
        while received.values.last != "STATE off", Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(received.values, ["HELLO", "STATE busy", "STATE off"])
    }

    func testPortsThatDoNotAnswerAreRejected() throws {
        var master: Int32 = -1, slave: Int32 = -1
        XCTAssertEqual(openpty(&master, &slave, nil, nil, nil), 0)
        defer { Darwin.close(master); Darwin.close(slave) }
        XCTAssertNil(SerialLink.connect(paths: [String(cString: ttyname(slave)), "/dev/does-not-exist"], timeout: 0.3))
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
