import Foundation
import OSLog

/// Low-level client for Discord's local RPC socket (`$TMPDIR/discord-ipc-N`).
///
/// Frames are `[opcode: UInt32 LE][length: UInt32 LE][JSON payload]`.
/// All socket work happens on a private serial queue; a dedicated thread
/// performs blocking reads so that `READY`, errors and pings are handled.
final class DiscordIPC: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(user: String?)
        case failed(String)
    }

    private enum Opcode: UInt32 {
        case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4
    }

    private let log = Logger(subsystem: "app.aura", category: "ipc")
    private let queue = DispatchQueue(label: "app.aura.ipc")
    private var fd: Int32 = -1
    private var generation = 0
    private let lock = NSLock()
    private var _clientID: String?
    /// The application the socket is (or is being) connected as. Thread-safe.
    var clientID: String? {
        get { lock.withLock { _clientID } }
        set { lock.withLock { _clientID = newValue } }
    }

    /// Called on the main queue whenever the connection status changes.
    var onStatusChange: (@Sendable (Status) -> Void)?
    /// Called on the main queue when Discord answers a command with an error.
    var onError: (@Sendable (String) -> Void)?

    // MARK: - Public API

    func connect(clientID: String) {
        let previous = self.clientID
        self.clientID = clientID
        queue.async { [self] in
            if fd >= 0, previous == clientID { return }
            closeSocket(sendClose: true)
            openSocket()
        }
    }

    func disconnect() {
        clientID = nil
        queue.async { [self] in
            closeSocket(sendClose: true)
            emit(.disconnected)
        }
    }

    /// Sends `SET_ACTIVITY`. Pass `nil` to clear the presence.
    func setActivity(_ activity: RichPresence?) {
        queue.async { [self] in
            guard fd >= 0 else { return }
            var args: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier)]
            if let activity { args["activity"] = activity.jsonObject }
            let payload: [String: Any] = [
                "cmd": "SET_ACTIVITY",
                "args": args,
                "nonce": UUID().uuidString,
            ]
            if !send(.frame, payload) { handleDrop() }
        }
    }

    var isConnected: Bool { queue.sync { fd >= 0 } }

    // MARK: - Socket lifecycle

    private static func candidatePaths() -> [String] {
        var bases: [String] = []
        let env = ProcessInfo.processInfo.environment
        for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"] {
            if let v = env[key], !v.isEmpty { bases.append(v) }
        }
        bases.append(NSTemporaryDirectory())
        bases.append("/tmp")
        var seen = Set<String>()
        var paths: [String] = []
        for base in bases {
            let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
            guard seen.insert(trimmed).inserted else { continue }
            for i in 0..<10 { paths.append("\(trimmed)/discord-ipc-\(i)") }
        }
        return paths
    }

    private func openSocket() {
        guard let clientID else { return }
        emit(.connecting)
        for path in Self.candidatePaths() where FileManager.default.fileExists(atPath: path) {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { continue }
            var noSigPipe: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
            guard path.utf8.count <= maxLen else { Darwin.close(s); continue }
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                raw.copyBytes(from: path.utf8)
                raw[path.utf8.count] = 0
            }
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            guard ok else { Darwin.close(s); continue }

            fd = s
            generation += 1
            log.info("Connected to \(path, privacy: .public)")
            _ = send(.handshake, ["v": 1, "client_id": clientID])
            startReader(fd: s, generation: generation)
            return
        }
        emit(.failed("Discord n'est pas lancé"))
    }

    private func closeSocket(sendClose: Bool) {
        guard fd >= 0 else { return }
        if sendClose { _ = send(.close, [:]) }
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        fd = -1
        generation += 1
    }

    private func handleDrop() {
        closeSocket(sendClose: false)
        emit(.disconnected)
    }

    // MARK: - Framing

    @discardableResult
    private func send(_ op: Opcode, _ object: [String: Any]) -> Bool {
        guard fd >= 0, let json = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var data = Data(capacity: 8 + json.count)
        withUnsafeBytes(of: op.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(json)
        return data.withUnsafeBytes { buf -> Bool in
            var offset = 0
            while offset < buf.count {
                let n = Darwin.write(fd, buf.baseAddress!.advanced(by: offset), buf.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    private func startReader(fd: Int32, generation gen: Int) {
        let thread = Thread { [weak self] in
            while let self {
                guard let (op, payload) = Self.readFrame(fd) else {
                    self.queue.async {
                        guard self.generation == gen else { return }
                        self.log.info("Socket closed by Discord")
                        self.handleDrop()
                    }
                    return
                }
                self.queue.async {
                    guard self.generation == gen else { return }
                    self.handle(op: op, payload: payload)
                }
            }
        }
        thread.name = "app.aura.ipc.reader"
        thread.start()
    }

    private static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            while offset < count {
                let n = Darwin.read(fd, buf.baseAddress!.advanced(by: offset), count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        return ok ? data : nil
    }

    private static func readFrame(_ fd: Int32) -> (UInt32, [String: Any])? {
        guard let header = readExactly(fd, 8) else { return nil }
        let op = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
        let len = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        guard len < 16 * 1024 * 1024, let body = readExactly(fd, Int(len)) else { return nil }
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        return (op, obj)
    }

    private static let debug = ProcessInfo.processInfo.environment["AURA_DEBUG"] != nil

    private func handle(op: UInt32, payload: [String: Any]) {
        if Self.debug, let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) {
            print("⇠ op\(op) \(text.prefix(600))")
            fflush(stdout)
        }
        switch Opcode(rawValue: op) {
        case .ping:
            _ = send(.pong, payload)
        case .close:
            let message = payload["message"] as? String ?? "Connexion refusée"
            log.error("Discord closed the connection: \(message, privacy: .public)")
            closeSocket(sendClose: false)
            emit(.failed(message))
        case .frame:
            let evt = payload["evt"] as? String
            if evt == "READY" {
                let data = payload["data"] as? [String: Any]
                let user = data?["user"] as? [String: Any]
                let name = (user?["global_name"] as? String) ?? (user?["username"] as? String)
                emit(.connected(user: name))
            } else if evt == "ERROR" {
                let data = payload["data"] as? [String: Any]
                let message = data?["message"] as? String ?? "Erreur inconnue"
                log.error("RPC error: \(message, privacy: .public)")
                let cb = onError
                DispatchQueue.main.async { cb?(message) }
            }
        default:
            break
        }
    }

    private func emit(_ status: Status) {
        let cb = onStatusChange
        DispatchQueue.main.async { cb?(status) }
    }
}
