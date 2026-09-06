import AppKit
import Foundation
import ImageIO
import Testing
@testable import AppshotShimCore

@Test("magic move controller has no Timer or per-frame window frame driver")
func magicMoveControllerUsesNoManualFrameDriver() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let controllerSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/AppshotShimCore/AppshotMagicMoveController.swift"
        ),
        encoding: .utf8
    )

    #expect(!controllerSource.contains("Timer("))
    #expect(!controllerSource.contains("func tick("))
    #expect(!controllerSource.contains("overlayWindow.setFrame("))
}

@Test("source overlay is committed before terminal snapshot rendering")
func magicMoveCommitsSourceFrameBeforeTransitionRendering() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let controllerSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/AppshotShimCore/AppshotMagicMoveController.swift"
        ),
        encoding: .utf8
    )
    let orderFront = try #require(
        controllerSource.range(of: "overlayWindow.orderFrontRegardless()")
    )
    let renderTerminal = try #require(
        controllerSource.range(of: "terminalPixels = try Self.renderTerminalSnapshotPixels(")
    )

    #expect(orderFront.lowerBound < renderTerminal.lowerBound)
}

@Test("terminal snapshot PNG encoding is moved off the main thread")
func magicMoveEncodesTransitionSnapshotInBackground() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let controllerSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/AppshotShimCore/AppshotMagicMoveController.swift"
        ),
        encoding: .utf8
    )

    #expect(
        controllerSource.contains(
            "AppshotBackgroundWork<AppshotTransitionSnapshotArtifact>"
        )
    )
}

@Test("magic move is committed before waiting for transition PNG persistence")
func magicMoveStartsBeforeTransitionSnapshotPersistenceFinishes() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let controllerSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/AppshotShimCore/AppshotMagicMoveController.swift"
        ),
        encoding: .utf8
    )
    let startAnimation = try #require(
        controllerSource.range(of: "startAnimation()\n        }\n        do {")
    )
    let waitForSnapshot = try #require(
        controllerSource.range(of: "transitionSnapshot = try transitionSnapshotWork.wait()")
    )

    #expect(startAnimation.lowerBound < waitForSnapshot.lowerBound)
}

@Test("spring sampling starts at zero and settles at one")
func springSamplingHasStableEndpoints() {
    let spring = AppshotMagicMoveSpring(
        response: 0.43,
        dampingFraction: 0.73,
        animationDuration: 1.44
    )

    #expect(spring.progress(at: 0) == 0)
    #expect(spring.progress(at: spring.animationDuration) == 1)
    #expect(spring.progress(at: 0.43) > 0.8)
}

@Test("top-left screen coordinates convert to AppKit without changing size")
func magicMoveConvertsScreenCoordinates() {
    let converted = AppshotMagicMoveGeometry.appKitFrame(
        fromTopLeftScreenFrame: CGRect(x: 100, y: 200, width: 464, height: 280),
        primaryDisplayHeight: 1_117
    )

    #expect(converted == CGRect(x: 100, y: 637, width: 464, height: 280))
}

@MainActor
@Test("overlay window is transparent click-through and cannot take focus")
func magicMoveOverlayNeverTakesFocus() {
    let window = AppshotMagicMoveOverlayWindow(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100)
    )

    #expect(!window.isOpaque)
    #expect(window.backgroundColor.alphaComponent == 0)
    #expect(window.ignoresMouseEvents)
    #expect(!window.canBecomeKey)
    #expect(!window.canBecomeMain)
    #expect(window.styleMask == .borderless)
}

@MainActor
@Test("terminal transition PNG is rendered from the overlay terminal layer")
func magicMoveRendersTerminalLayerSnapshot() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let screenshotURL = directory.appendingPathComponent("source.png")
    let transitionURL = directory.appendingPathComponent("terminal.png")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    try writeMagicMoveSolidPNG(
        color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
        width: 400,
        height: 300,
        to: screenshotURL
    )
    let icon = magicMoveSolidImage(
        color: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1),
        width: 24,
        height: 24
    )
    let target = AppshotAnimationTarget(
        destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
        destinationCornerRadius: 12,
        destinationBackgroundColor: AppshotRGBColor(red: 245, green: 245, blue: 245),
        destinationPrimaryTextColor: AppshotRGBColor(red: 0, green: 0, blue: 255),
        codexDisplay: .init(
            id: 1,
            bounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            workArea: CGRect(x: 0, y: 25, width: 1_728, height: 1_067),
            scaleFactor: 2
        )
    )

    let move = try AppshotMagicMoveController.prepare(
        screenshotURL: screenshotURL,
        sourceFrame: CGRect(x: 20, y: 40, width: 800, height: 600),
        applicationIcon: icon,
        title: "Test Window",
        animationTarget: target,
        transitionSnapshotURL: transitionURL,
        primaryDisplayHeight: 1_117,
        showOverlay: false
    )

    #expect(move.transitionSnapshot.url == transitionURL)
    #expect(move.transitionSnapshot.transitionSnapshotHeight == 161)
    #expect(move.spring.dampingFraction == 0.73)
    #expect(move.sourceFrame == CGRect(x: 20, y: 40, width: 800, height: 600))
    #expect(move.destinationFrame == target.destinationFrame)

    let source = try #require(CGImageSourceCreateWithURL(transitionURL as CFURL, nil))
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 464)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 322)

    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: transitionURL)))
    #expect(containsMagicMovePixel(in: bitmap) { color in
        color.redComponent > color.greenComponent + 0.4
            && color.redComponent > color.blueComponent + 0.4
            && color.alphaComponent > 0.8
    })
    #expect(containsMagicMovePixel(in: bitmap) { color in
        color.greenComponent > color.redComponent + 0.4
            && color.greenComponent > color.blueComponent + 0.4
            && color.alphaComponent > 0.8
    })
}

@MainActor
@Test("magic move prepares from an in-memory screenshot without a source PNG")
func magicMoveUsesInMemoryScreenshot() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let transitionURL = directory.appendingPathComponent("terminal.png")
    let screenshot = try #require(magicMoveSolidCGImage(
        color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
        width: 400,
        height: 300
    ))
    let icon = magicMoveSolidImage(
        color: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1),
        width: 24,
        height: 24
    )
    let target = AppshotAnimationTarget(
        destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
        destinationCornerRadius: 12,
        destinationBackgroundColor: AppshotRGBColor(red: 245, green: 245, blue: 245),
        destinationPrimaryTextColor: AppshotRGBColor(red: 0, green: 0, blue: 255),
        codexDisplay: .init(
            id: 1,
            bounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            workArea: CGRect(x: 0, y: 25, width: 1_728, height: 1_067),
            scaleFactor: 2
        )
    )

    let move = try AppshotMagicMoveController.prepare(
        screenshotImage: screenshot,
        sourceFrame: CGRect(x: 20, y: 40, width: 800, height: 600),
        applicationIcon: icon,
        title: "Test Window",
        animationTarget: target,
        transitionSnapshotURL: transitionURL,
        primaryDisplayHeight: 1_117,
        showOverlay: false
    )

    #expect(move.transitionSnapshot.url == transitionURL)
    #expect(FileManager.default.fileExists(atPath: transitionURL.path))
}

@MainActor
@Test("magic move accepts a predecoded in-memory application icon")
func magicMoveUsesPredecodedApplicationIcon() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let transitionURL = directory.appendingPathComponent("terminal.png")
    let screenshot = try #require(magicMoveSolidCGImage(
        color: .red,
        width: 400,
        height: 300
    ))
    let icon = try #require(magicMoveSolidCGImage(
        color: .green,
        width: 24,
        height: 24
    ))
    let target = AppshotAnimationTarget(
        destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
        destinationCornerRadius: 12,
        destinationBackgroundColor: AppshotRGBColor(red: 245, green: 245, blue: 245),
        destinationPrimaryTextColor: AppshotRGBColor(red: 0, green: 0, blue: 255),
        codexDisplay: .init(
            id: 1,
            bounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            workArea: CGRect(x: 0, y: 25, width: 1_728, height: 1_067),
            scaleFactor: 2
        )
    )

    let move = try AppshotMagicMoveController.prepare(
        screenshotImage: screenshot,
        sourceFrame: CGRect(x: 20, y: 40, width: 800, height: 600),
        applicationIconImage: icon,
        title: "Test Window",
        animationTarget: target,
        transitionSnapshotURL: transitionURL,
        primaryDisplayHeight: 1_117,
        showOverlay: false
    )

    #expect(move.transitionSnapshot.url == transitionURL)
}

@MainActor
@Test("coordinator URL entry still rejects a shared source and transition path")
func magicMoveCoordinatorRejectsSharedSnapshotPath() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sharedURL = directory.appendingPathComponent("shared.png")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    try writeMagicMoveSolidPNG(
        color: .red,
        width: 400,
        height: 300,
        to: sharedURL
    )
    let target = AppshotAnimationTarget(
        destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
        destinationCornerRadius: 12,
        destinationBackgroundColor: AppshotRGBColor(red: 245, green: 245, blue: 245),
        destinationPrimaryTextColor: AppshotRGBColor(red: 0, green: 0, blue: 255),
        codexDisplay: .init(
            id: 1,
            bounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            workArea: CGRect(x: 0, y: 25, width: 1_728, height: 1_067),
            scaleFactor: 2
        )
    )
    let coordinator = AppshotMagicMoveCoordinator()

    do {
        let unexpectedMove = try coordinator.start(
            requestID: UUID().uuidString,
            screenshotURL: sharedURL,
            sourceFrame: CGRect(x: 20, y: 40, width: 800, height: 600),
            applicationIcon: magicMoveSolidImage(
                color: .green,
                width: 24,
                height: 24
            ),
            title: "Test Window",
            animationTarget: target,
            transitionSnapshotURL: sharedURL
        )
        unexpectedMove.cancel()
        Issue.record("Expected the coordinator to reject a shared snapshot path")
    } catch AppshotMagicMoveControllerError.screenshotAndTransitionPathsMatch {
        // Expected.
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func writeMagicMoveSolidPNG(
    color: NSColor,
    width: Int,
    height: Int,
    to destination: URL
) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: destination, options: .atomic)
}

private func magicMoveSolidImage(
    color: NSColor,
    width: Int,
    height: Int
) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}

private func magicMoveSolidCGImage(
    color: NSColor,
    width: Int,
    height: Int
) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private func containsMagicMovePixel(
    in bitmap: NSBitmapImageRep,
    matching predicate: (NSColor) -> Bool
) -> Bool {
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard
                let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            else {
                continue
            }
            if predicate(color) {
                return true
            }
        }
    }
    return false
}
