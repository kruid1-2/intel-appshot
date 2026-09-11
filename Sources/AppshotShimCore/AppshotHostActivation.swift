import AppKit
import OSLog

enum AppshotActivationLog {
    static let logger = Logger(subsystem: "com.openai.sky.CUAService", category: "AppshotActivation")
}

/// A one-shot foreground gate, not a Computer Use action or an animation driver.
@MainActor
public struct AppshotHostActivation {
    enum Result: String {
        case ready, rejected, timedOut, cancelled
    }

    let isFrontmost: () -> Bool
    private let requestActivation: () -> Bool
    private let timeout: Duration

    init(
        isFrontmost: @escaping () -> Bool,
        requestActivation: @escaping () -> Bool,
        timeout: Duration = .seconds(2)
    ) {
        self.isFrontmost = isFrontmost
        self.requestActivation = requestActivation
        self.timeout = timeout
    }

    /// Pin one running regular Codex process. Never launch an app or activate the
    /// Helper/Apple Event worker, and refuse ambiguous multiple host instances.
    public static func codex() -> Self? {
        let candidates = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).filter { !$0.isTerminated && $0.activationPolicy == .regular }
        guard candidates.count == 1, let host = candidates.first else { return nil }
        let pid = host.processIdentifier
        return Self(
            isFrontmost: {
                !host.isTerminated && host.isActive
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            },
            requestActivation: {
                guard !host.isTerminated else { return false }
                AppshotActivationLog.logger.info("activation-request hostPID=\(pid)")
                return host.activate(options: [])
            }
        )
    }

    func waitUntilFrontmost() async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        if isFrontmost() { return .ready }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        guard requestActivation() else { return .rejected }
        while !Task.isCancelled {
            if isFrontmost() { return .ready }
            guard ContinuousClock.now < deadline else { return .timedOut }
            do {
                // Suspends the task; never pumps a nested run loop or blocks the
                // Apple Event reply. No polling survives into the animation.
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return .cancelled
            }
        }
        return .cancelled
    }
}
