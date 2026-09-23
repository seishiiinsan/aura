import Darwin
import Foundation

/// Lists the user's processes with their arguments (libproc + sysctl, no permission needed).
enum ProcessScanner {
    struct Process: Sendable {
        var pid: pid_t
        var executablePath: String
        var arguments: [String]
        var startDate: Date?
    }

    static func allProcesses() -> [Process] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let uid = getuid()
        return pids.prefix(Int(max(0, n))).compactMap { pid in
            guard pid > 0, let info = kinfo(pid), info.kp_eproc.e_ucred.cr_uid == uid else { return nil }
            var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = len > 0 ? String(cString: pathBuf) : ""
            let tv = info.kp_proc.p_starttime
            let start = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
            return Process(pid: pid, executablePath: path, arguments: arguments(pid), startDate: start)
        }
    }

    private static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// argv of a process via KERN_PROCARGS2 (argc, exec path, then NUL-separated args).
    static func arguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 } // skip exec path
        while i < size, buffer[i] == 0 { i += 1 } // skip padding
        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}
