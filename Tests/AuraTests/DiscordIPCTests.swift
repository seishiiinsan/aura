import Darwin
import Foundation
import Testing
@testable import Aura

/// Runs a fake Discord client socket and checks Aura's IPC framing end to end.
@Suite("Discord IPC protocol", .serialized)
struct DiscordIPCTests {
    private final class FakeDiscord: @unchecked Sendable {
        let dir: String
        private var server: Int32 = -1
        private(set) var frames: [(op: UInt32, json: [String: Any])] = []
        private let lock = NSLock()

        init() {
            dir = "/tmp/aura-ipc-\(getpid())-\(Int.random(in: 0..<100_000))"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        func start() {
            let path = dir + "/discord-ipc-0"
            server = socket(AF_UNIX, SOCK_STREAM, 0)
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                raw.copyBytes(from: path.utf8)
                raw[path.utf8.count] = 0
            }
            _ = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            listen(server, 1)
            Thread.detachNewThread { [self] in
                let client = accept(server, nil, nil)
                guard client >= 0 else { return }
                while let frame = read(client) {
                    lock.withLock { frames.append(frame) }
                    if frame.op == 0 { // handshake → READY
                        write(client, op: 1, ["cmd": "DISPATCH", "evt": "READY", "data": ["user": ["username": "tester", "global_name": "Tester"]]])
                    }
                }
            }
        }

        func received() -> [(op: UInt32, json: [String: Any])] { lock.withLock { frames } }

        private func read(_ fd: Int32) -> (op: UInt32, json: [String: Any])? {
            var header = [UInt8](repeating: 0, count: 8)
            guard recv(fd, &header, 8, MSG_WAITALL) == 8 else { return nil }
            let op = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
            let len = Int(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
            var body = [UInt8](repeating: 0, count: len)
            if len > 0 { guard recv(fd, &body, len, MSG_WAITALL) == len else { return nil } }
            let json = (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any] ?? [:]
            return (op, json)
        }

        private func write(_ fd: Int32, op: UInt32, _ obj: [String: Any]) {
            let json = try! JSONSerialization.data(withJSONObject: obj)
            var data = Data()
            withUnsafeBytes(of: op.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(json.count).littleEndian) { data.append(contentsOf: $0) }
            data.append(json)
            _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
        }

        deinit {
            close(server)
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    @Test func handshakeAndSetActivity() async throws {
        let fake = FakeDiscord()
        fake.start()
        setenv("XDG_RUNTIME_DIR", fake.dir, 1)
        defer { unsetenv("XDG_RUNTIME_DIR") }

        let ipc = DiscordIPC()
        let connected = Mutex<String?>(nil)
        ipc.onStatusChange = { status in
            if case .connected(let user) = status { connected.set(user) }
        }
        ipc.connect(clientID: "1552407073902297088")

        var p = RichPresence(type: .listening)
        p.details = "Humain"
        p.state = "BEN plg"
        for _ in 0..<50 where connected.get() == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(connected.get() == "Tester")

        ipc.setActivity(p)
        for _ in 0..<50 where fake.received().count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        let frames = fake.received()
        #expect(frames.first?.op == 0)
        #expect(frames.first?.json["client_id"] as? String == "1552407073902297088")
        let set = frames.last?.json
        #expect(set?["cmd"] as? String == "SET_ACTIVITY")
        let activity = (set?["args"] as? [String: Any])?["activity"] as? [String: Any]
        #expect(activity?["details"] as? String == "Humain")
        #expect(activity?["type"] as? Int == 2)
        ipc.disconnect()
    }
}

/// Tiny lock-protected box for values written from callbacks.
final class Mutex<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ v: T) { lock.withLock { value = v } }
}
