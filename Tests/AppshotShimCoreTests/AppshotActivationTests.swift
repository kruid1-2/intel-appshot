import AppKit
import ImageIO
import QuartzCore
import Testing
@testable import AppshotShimCore

@Suite(.serialized)
@MainActor
struct AppshotActivationTests {
    // Catches eager orderFront/startAnimation inside preparation, before host readiness.
    @Test func preparationProducesSnapshotWithoutShowingOrAnimating() throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        #expect(!fixture.window.isVisible)
        #expect(fixture.window.contentView?.layer?.sublayers?.allSatisfy {
            ($0.animationKeys() ?? []).isEmpty
        } == true)
        #expect(CGImageSourceCreateWithURL(fixture.move.transitionSnapshot.url as CFURL, nil) != nil)
        #expect(fixture.move.transitionSnapshot.transitionSnapshotHeight == 161)
    }

    @Test func shutterPrecedesActivationButFlightWaitsForActualForeground() async throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        let host = ActivationHostFixture()
        let originalPNG = try Data(contentsOf: fixture.move.transitionSnapshot.url)
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-wait")
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-duplicate")
        try await eventually { fixture.window.isVisible }
        #expect(host.activationRequests == 0)
        let root = try #require(fixture.window.contentView?.layer)
        // Composer can independently activate its host on screenshot receipt.
        // A source-aligned replica must cover that switch underneath the flash.
        #expect(root.sublayers?.first?.opacity == 1)
        // The real window already has a shadow: shutter's replica must not double it.
        #expect(root.sublayers?.first?.sublayers?.first?.shadowOpacity == 0)
        let shutter = try #require(root.sublayers?.first { $0.name == "appshot.shutter" })
        #expect(shutter.animation(forKey: "appshotShutterFadeIn") != nil)
        try await eventually { host.activationRequests == 1 }
        #expect(fixture.window.isVisible)
        let sourceShutterFrame = shutter.frame
        #expect(shutter.animation(forKey: "magicMove.position") == nil)
        // An early Composer acknowledgment must not close a not-yet-started flight.
        fixture.move.markComposerHandoffFinished()
        host.frontmost = true
        try await eventually { shutter.animation(forKey: "magicMove.position") != nil }
        #expect(host.activationRequests == 1)
        let movement = try #require(shutter.animation(forKey: "magicMove.position") as? CABasicAnimation)
        #expect((movement.fromValue as? NSValue)?.pointValue == CGPoint(x: sourceShutterFrame.midX, y: sourceShutterFrame.midY))
        #expect(shutter.animation(forKey: "appshotShutterFadeOut") != nil)
        let mask = try #require(root.sublayers?.first?.mask as? CAGradientLayer)
        #expect(mask.animation(forKey: "magicMove.colors") == nil)
        let colors = try #require(mask.colors as? [CGColor])
        #expect(colors.last?.alpha == 0)
        #expect(fixture.window.contentView?.layer?.sublayers?.contains {
            !($0.animationKeys() ?? []).isEmpty
        } == true)
        #expect(try Data(contentsOf: fixture.move.transitionSnapshot.url) == originalPNG)
        try await eventually(timeout: .seconds(3)) { !fixture.window.isVisible }
    }

    @Test func alreadyForegroundDoesNotRequestActivationAndWaitsForHandoffToClose() async throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        let host = ActivationHostFixture()
        host.frontmost = true
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-active")
        try await eventually { fixture.window.isVisible }
        #expect(host.activationRequests == 0)
        try await Task.sleep(for: .seconds(fixture.move.spring.animationDuration + 0.2))
        #expect(fixture.window.isVisible)
        fixture.move.markComposerHandoffFinished()
        #expect(!fixture.window.isVisible)
    }

    @Test func cancelledWaitCannotResurrectOverlay() async throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        let host = ActivationHostFixture()
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-cancel")
        try await eventually { host.activationRequests == 1 }
        fixture.move.cancel()
        host.frontmost = true
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-restart")
        try await Task.sleep(for: .milliseconds(80))
        #expect(!fixture.window.isVisible)
        #expect(host.activationRequests == 1)
    }

    @Test func cancellationBeforeTaskRunsDoesNotActivateHost() async throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        let host = ActivationHostFixture()
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-cancel-before-start")
        fixture.move.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(host.activationRequests == 0)
        #expect(!fixture.window.isVisible)
    }

    @Test func cancellationDuringShutterCannotActivateOrStartLateFlight() async throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        let host = ActivationHostFixture()
        fixture.move.startWhenHostIsReady(host.activation, requestID: "cancel-shutter")
        try await eventually { fixture.window.isVisible }
        fixture.move.cancel()
        host.frontmost = true
        try await Task.sleep(for: .milliseconds(300))
        #expect(host.activationRequests == 0)
        #expect(!fixture.window.isVisible)
        let shutter = fixture.window.contentView?.layer?.sublayers?.first { $0.name == "appshot.shutter" }
        #expect((shutter?.animationKeys() ?? []).isEmpty)
    }

    @Test func activationTimeoutDoesNotShowLateOverlayOrLoseSnapshot() async throws {
        let fixture = try ActivationMoveFixture()
        defer { fixture.cleanUp() }
        let host = ActivationHostFixture()
        fixture.move.startWhenHostIsReady(host.activation, requestID: "test-timeout")
        try await eventually { host.activationRequests == 1 }
        try await Task.sleep(for: .milliseconds(180))
        host.frontmost = true
        try await Task.sleep(for: .milliseconds(80))
        #expect(!fixture.window.isVisible)
        #expect(host.activationRequests == 1)
        #expect(CGImageSourceCreateWithURL(fixture.move.transitionSnapshot.url as CFURL, nil) != nil)
    }

    @Test func rejectedOrMissingHostLeavesNoOverlay() async throws {
        for missing in [false, true] {
            let fixture = try ActivationMoveFixture()
            defer { fixture.cleanUp() }
            let host = ActivationHostFixture()
            host.acceptsActivation = false
            fixture.move.startWhenHostIsReady(missing ? nil : host.activation, requestID: "test-reject")
            try await Task.sleep(for: .milliseconds(300))
            host.frontmost = true
            fixture.move.startWhenHostIsReady(host.activation, requestID: "test-no-retry")
            try await Task.sleep(for: .milliseconds(50))
            #expect(!fixture.window.isVisible)
            #expect(host.activationRequests == (missing ? 0 : 1))
        }
    }
}

@MainActor
private final class ActivationHostFixture {
    var frontmost = false
    var acceptsActivation = true
    var activationRequests = 0

    var activation: AppshotHostActivation {
        AppshotHostActivation(
            isFrontmost: { self.frontmost },
            requestActivation: {
                self.activationRequests += 1
                return self.acceptsActivation
            },
            timeout: .milliseconds(120)
        )
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(1),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
}

@MainActor
private final class ActivationMoveFixture {
    let directory: URL
    let move: AppshotMagicMoveController
    let window: NSWindow

    init() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try #require(CGContext(
            data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        let image = try #require(context.makeImage())
        let previous = Set(NSApp.windows.map(ObjectIdentifier.init))
        move = try AppshotMagicMoveController.prepare(
            screenshotImage: image,
            sourceFrame: CGRect(x: 40, y: 80, width: 320, height: 200),
            applicationIconImage: image,
            title: "Appshot activation test",
            animationTarget: AppshotAnimationTarget(
                destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
                destinationCornerRadius: 12,
                destinationBackgroundColor: .init(red: 245, green: 245, blue: 245),
                destinationPrimaryTextColor: .init(red: 0, green: 0, blue: 0),
                codexDisplay: .init(
                    id: 1, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                    workArea: CGRect(x: 0, y: 25, width: 1728, height: 1067), scaleFactor: 2
                )
            ),
            transitionSnapshotURL: directory.appendingPathComponent("transition.png")
        )
        window = try #require(NSApp.windows.first {
            $0 is AppshotMagicMoveOverlayWindow && !previous.contains(ObjectIdentifier($0))
        })
    }

    func cleanUp() {
        move.cancel()
        try? FileManager.default.removeItem(at: directory)
    }
}
