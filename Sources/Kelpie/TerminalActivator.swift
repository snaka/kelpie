import AppKit
import Darwin

/// Brings the terminal that hosts herdr to the front.
///
/// herdr has no API for this, so Kelpie finds the hosting app by walking the
/// process tree: a TUI client is a `herdr` process without the `server`
/// subcommand, and its first ancestor living inside an `.app` bundle is the
/// terminal. Inspecting the user's own processes needs no entitlement in a
/// non-sandboxed app.
///
/// `AppCoordinator.jump(to:)` calls `activateHerdrHost()` after sending
/// `agent.focus`, regardless of whether that request succeeded: a click that
/// appears to do nothing is worse for the user than one that raises the
/// hosting terminal on a slightly stale pane, and a focus failure most likely
/// means the target pane is already gone rather than that herdr itself is
/// unreachable.
enum TerminalActivator {

    /// The walk inspects every process on the machine, so it runs off the main
    /// actor — it is reached from every jump and every notification activation,
    /// and stalling the main actor there would stutter the whole UI. Only
    /// `NSRunningApplication.activate` needs to be back on the main actor.
    @MainActor
    static func activateHerdrHost() async {
        let hostPID = await Task.detached(priority: .userInitiated) { hostApplicationPID() }.value
        guard let hostPID, let app = NSRunningApplication(processIdentifier: hostPID) else {
            // No attached client: focusing herdr was still worth doing, and the
            // right pane will be selected the next time it is opened.
            return
        }
        app.activate(options: [.activateAllWindows])
    }

    /// The first herdr client whose ancestor chain reaches an `.app` bundle.
    static func hostApplicationPID() -> pid_t? {
        for pid in herdrClientPIDs() {
            if let appPID = appAncestor(of: pid) { return appPID }
        }
        return nil
    }

    static func herdrClientPIDs() -> [pid_t] {
        // One reader for the whole walk. It used to re-read KERN_ARGMAX and
        // allocate a fresh buffer of that size for every process on the
        // machine — 1 MB each on macOS, so several hundred megabytes of churn
        // per click, on the main actor.
        guard var reader = ProcessArgumentsReader() else { return [] }
        return allPIDs().filter { pid in
            guard let arguments = reader.arguments(of: pid), let first = arguments.first else { return false }
            guard (first as NSString).lastPathComponent == "herdr" else { return false }
            // The server runs as `herdr server`; only bare `herdr` is a client.
            return !arguments.dropFirst().contains("server")
        }
    }

    static func appAncestor(of pid: pid_t) -> pid_t? {
        var current = pid
        // Bounded so a cycle or a very deep tree cannot spin forever.
        for _ in 0..<16 {
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            if let path = executablePath(parent), path.contains(".app/Contents/MacOS/") {
                return parent
            }
            current = parent
        }
        return nil
    }

    // MARK: - Process inspection

    private static func allPIDs() -> [pid_t] {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size)
        count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, count)
        guard count > 0 else { return [] }
        return pids.filter { $0 > 0 }
    }

    /// Uses the "short" BSD info, not the full `proc_bsdinfo`/`PROC_PIDTBSDINFO`
    /// pair: on this machine the client's ancestor chain passes through
    /// `/usr/bin/login`, a setuid-root process, and `PROC_PIDTBSDINFO` fails
    /// with `EPERM` there because it is owned by a different uid. The short
    /// variant exposes only pid/ppid/pgid/status/comm and is readable across
    /// uids, which is exactly what the ancestor walk needs.
    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
        guard size == Int32(MemoryLayout<proc_bsdshortinfo>.size) else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    /// `libproc`'s `PROC_PIDPATHINFO_MAXSIZE` macro (`4 * MAXPATHLEN`) is not
    /// importable on this SDK, so its documented value (4 * 1024) is used
    /// directly; `proc_pidpath` truncates rather than overruns a shorter
    /// buffer, so an undersized value here would only fail closed.
    private static let maxPathSize = 4 * 1024

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: maxPathSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[0..<Int(length)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Reads argv from the kernel's process arguments area, reusing a single
    /// `KERN_ARGMAX`-sized buffer across every process it is asked about.
    /// `KERN_ARGMAX` is a boot-time constant, so reading it once is enough.
    private struct ProcessArgumentsReader {
        private let capacity: Int
        private var buffer: [CChar]

        init?() {
            var argMax: Int32 = 0
            var size = MemoryLayout<Int32>.size
            var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
            guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
            capacity = Int(argMax)
            buffer = [CChar](repeating: 0, count: capacity)
        }

        /// Stale bytes from the previous process are harmless: `sysctl` writes
        /// the real length back into `bufferSize`, and parsing never reads past
        /// it.
        mutating func arguments(of pid: pid_t) -> [String]? {
            var bufferSize = capacity
            var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0,
                  bufferSize > MemoryLayout<Int32>.size else {
                return nil
            }

            var argc: Int32 = 0
            memcpy(&argc, buffer, MemoryLayout<Int32>.size)
            var cursor = MemoryLayout<Int32>.size

            // Skip the executable path, then its NUL padding.
            while cursor < bufferSize, buffer[cursor] != 0 { cursor += 1 }
            while cursor < bufferSize, buffer[cursor] == 0 { cursor += 1 }

            var arguments: [String] = []
            var chunk: [UInt8] = []
            while cursor < bufferSize, arguments.count < Int(argc) {
                if buffer[cursor] == 0 {
                    arguments.append(String(decoding: chunk, as: UTF8.self))
                    chunk = []
                } else {
                    chunk.append(UInt8(bitPattern: buffer[cursor]))
                }
                cursor += 1
            }
            return arguments
        }
    }
}
