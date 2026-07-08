import Foundation

/// `Apps` backed by `xcrun simctl install <udid> <path>`.
///
/// The orchestration here is pure: argv assembly (delegated to
/// `AppBundle.installArguments`) + the `Subprocess` exit handshake. The
/// `Foundation.Process` plumbing lives in `HostSubprocess` (already
/// vendored for `LogStream`), so this file is unit-covered end-to-end
/// via `MockSubprocess` — only the real spawn is integration-only.
final class SimctlApps: Apps, @unchecked Sendable {
    private let udid: String
    private let subprocess: any Subprocess
    private let xcrun: URL

    init(
        udid: String,
        subprocess: any Subprocess = HostSubprocess(),
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun")
    ) {
        self.udid = udid
        self.subprocess = subprocess
        self.xcrun = xcrun
    }

    func install(_ app: AppBundle) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try subprocess.run(
                    executable: xcrun,
                    arguments: app.installArguments(udid: udid),
                    onBytes: { _ in },
                    onExit: { code in
                        if code == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: AppsError.installFailed(status: code))
                        }
                    }
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
