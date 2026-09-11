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
        primaryDisplayHeight: 1_117
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
@Test("terminal snapshot includes exterior shadow and preserves its content coordinates")
func magicMovePreservesExteriorShadowPixels() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("padded-terminal.png")
    let screenshot = try #require(magicMoveSolidCGImage(color: .red, width: 400, height: 300))
    let icon = try #require(magicMoveSolidCGImage(color: .green, width: 24, height: 24))
    let move = try AppshotMagicMoveController.prepare(
        screenshotImage: screenshot,
        sourceFrame: CGRect(x: 20, y: 40, width: 800, height: 600),
        applicationIconImage: icon,
        title: "Test Window",
        animationTarget: AppshotAnimationTarget(
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
        ),
        transitionSnapshotURL: url,
        primaryDisplayHeight: 1_117,
        preservesExteriorShadow: true
    )

    // Composer layout height continues to describe the original content, not padding.
    #expect(move.transitionSnapshot.transitionSnapshotHeight == 161)
    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    #expect(bitmap.pixelsWide > 464)
    #expect(bitmap.pixelsHigh > 322)
    let imageSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    )
    let png = try #require(properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])
    let description = try #require(png[kCGImagePropertyPNGDescription] as? String)
    let prefix = "codex-appshot-layout-v1:"
    #expect(description.hasPrefix(prefix))
    let layout = try #require(JSONSerialization.jsonObject(
        with: Data(description.dropFirst(prefix.count).utf8)
    ) as? [String: Double])
    let x = try #require(layout["x"])
    let y = try #require(layout["y"])
    #expect(layout["width"] == 464)
    #expect(layout["height"] == 322)
    #expect(x > 0 && y > 0)
    // The 400:300 screenshot fits to 186.67 x 140 pt, centered in 232 pt.
    // Sample 8 px outside its actual left/right edges (45.33 / 418.67 px),
    // not the removed solid backing's edges. The shadow follows source alpha.
    #expect(try #require(bitmap.colorAt(x: Int(x) + 37, y: Int(y) + 140)).alphaComponent > 0.01)
    #expect(try #require(bitmap.colorAt(x: Int(x) + 427, y: Int(y) + 140)).alphaComponent > 0.01)
    #expect(try #require(bitmap.colorAt(x: Int(x) + 232, y: Int(y) - 8)).alphaComponent > 0.01)
    for column in 0..<bitmap.pixelsWide {
        #expect(try #require(bitmap.colorAt(x: column, y: 0)).alphaComponent < 0.005)
    }
    for row in 0..<bitmap.pixelsHigh {
        #expect(try #require(bitmap.colorAt(x: 0, y: row)).alphaComponent < 0.005)
        #expect(try #require(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: row)).alphaComponent < 0.005)
    }
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
        primaryDisplayHeight: 1_117
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
        primaryDisplayHeight: 1_117
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

@MainActor
@Test("terminal PNG fades content and shadow without fading icon or title", arguments: [1.0, 2.0])
func magicMoveTerminalFadeHasNoHardBottomEdge(scale: Double) throws {
    // Removing the shared effects mask must expose the original opaque-to-shadow jump.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("fade.png")
    let move = try AppshotMagicMoveController.prepare(
        screenshotImage: #require(magicMoveSolidCGImage(color: .red, width: 464, height: 280)),
        sourceFrame: CGRect(x: 20, y: 40, width: 928, height: 560),
        applicationIconImage: #require(magicMoveSolidCGImage(color: .green, width: 24, height: 24)),
        title: "Test Window",
        animationTarget: AppshotAnimationTarget(
            destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
            destinationCornerRadius: 12,
            destinationBackgroundColor: AppshotRGBColor(red: 255, green: 255, blue: 255),
            destinationPrimaryTextColor: AppshotRGBColor(red: 0, green: 0, blue: 255),
            codexDisplay: .init(id: 1,
                bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                workArea: CGRect(x: 0, y: 25, width: 1728, height: 1067),
                scaleFactor: scale)
        ),
        transitionSnapshotURL: url,
        primaryDisplayHeight: 1117
    )
    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    #expect(move.transitionSnapshot.transitionSnapshotHeight == 161)
    #expect(bitmap.pixelsWide == Int(232 * scale))
    #expect(bitmap.pixelsHigh == Int(161 * scale))
    func alpha(_ y: Double) throws -> CGFloat {
        try #require(bitmap.colorAt(x: Int(40 * scale), y: Int(y * scale))).alphaComponent
    }
    #expect(try alpha(20) > 0.98)
    #expect(try alpha(85) < 0.95)
    #expect(try alpha(110) < alpha(85))
    #expect(try alpha(132) < 0.08)
    // Scan through the former card/background boundary and its shadow, away from text.
    for row in Int(125 * scale)..<Int(145 * scale) {
        let a = try #require(bitmap.colorAt(x: Int(8 * scale), y: row)).alphaComponent
        let b = try #require(bitmap.colorAt(x: Int(8 * scale), y: row + 1)).alphaComponent
        #expect(abs(a - b) < 0.03)
    }
    #expect(try alpha(141) < 0.005)
    #expect(containsMagicMovePixel(in: bitmap) { color in
        color.greenComponent > 0.9 && color.redComponent < 0.1 && color.alphaComponent > 0.98
    })
    #expect(containsMagicMovePixel(in: bitmap) { color in
        color.blueComponent > 0.9 && color.redComponent < 0.1 && color.alphaComponent > 0.98
    })
}

@MainActor
@Test("transparent screenshot edges and aspect-fit margins never expose a white backing", arguments: [false, true])
func magicMoveHasNoOpaqueSideBacking(portrait: Bool) throws {
    let width = portrait ? 400 : 464
    let height = portrait ? 600 : 280
    let context = try #require(CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 2, y: 0, width: width - 4, height: height))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let move = try AppshotMagicMoveController.prepare(
        screenshotImage: #require(context.makeImage()),
        sourceFrame: CGRect(x: 20, y: 40, width: width, height: height),
        applicationIconImage: #require(magicMoveSolidCGImage(color: .green, width: 24, height: 24)),
        title: "Side edges",
        animationTarget: .init(destinationFrame: CGRect(x: 100, y: 200, width: 232, height: 140),
            destinationCornerRadius: 12,
            destinationBackgroundColor: .init(red: 255, green: 255, blue: 255),
            destinationPrimaryTextColor: .init(red: 0, green: 0, blue: 0),
            codexDisplay: .init(id: 1, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                workArea: CGRect(x: 0, y: 25, width: 1728, height: 1067), scaleFactor: 2)),
        transitionSnapshotURL: directory.appendingPathComponent("terminal.png"),
        primaryDisplayHeight: 1117)
    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: move.transitionSnapshot.url)))
    for x in [0, 463] {
        let color = try #require(bitmap.colorAt(x: x, y: 80)?.usingColorSpace(.deviceRGB))
        // Transparent margin or a soft black shadow, never an opaque/light stripe.
        #expect(color.alphaComponent < 0.25)
        #expect(color.redComponent < 0.05)
        #expect(color.greenComponent < 0.05)
        #expect(color.blueComponent < 0.05)
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
