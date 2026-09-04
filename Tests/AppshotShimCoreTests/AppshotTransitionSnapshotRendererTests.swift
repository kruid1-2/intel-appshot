import AppKit
import Foundation
import ImageIO
import Testing
@testable import AppshotShimCore

@MainActor
@Test("transition renderer writes a distinct Retina PNG with screenshot icon and title")
func transitionRendererComposesVisualCard() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let screenshotURL = directory.appendingPathComponent("final.png")
    let transitionURL = directory.appendingPathComponent("transition.png")
    try writeSolidPNG(
        color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
        width: 200,
        height: 100,
        to: screenshotURL
    )
    let icon = solidImage(
        color: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1),
        width: 24,
        height: 24
    )
    let target = AppshotAnimationTarget(
        destinationFrameWidth: 232,
        displayScaleFactor: 2,
        destinationPrimaryTextColor: AppshotRGBColor(
            red: 0,
            green: 0,
            blue: 255
        )
    )

    let artifact = try AppshotTransitionSnapshotRenderer.render(
        screenshotURL: screenshotURL,
        applicationIcon: icon,
        title: "Finder",
        animationTarget: target,
        destinationURL: transitionURL
    )

    #expect(artifact.url == transitionURL)
    #expect(artifact.url != screenshotURL)
    #expect(artifact.transitionSnapshotHeight == 161)
    #expect(FileManager.default.fileExists(atPath: transitionURL.path))

    let properties = try imageProperties(at: transitionURL)
    #expect(properties.width == 464)
    #expect(properties.height == 322)

    let bitmap = try #require(
        NSBitmapImageRep(data: Data(contentsOf: transitionURL))
    )
    #expect(containsPixel(in: bitmap) { color in
        color.redComponent > color.greenComponent + 0.4
            && color.redComponent > color.blueComponent + 0.4
            && color.alphaComponent > 0.8
    })
    #expect(containsPixel(in: bitmap) { color in
        color.greenComponent > color.redComponent + 0.4
            && color.greenComponent > color.blueComponent + 0.4
            && color.alphaComponent > 0.8
    })
    #expect(containsPixel(in: bitmap) { color in
        color.blueComponent > color.redComponent + 0.3
            && color.blueComponent > color.greenComponent + 0.3
            && color.alphaComponent > 0.2
    })
}

private func writeSolidPNG(
    color: NSColor,
    width: Int,
    height: Int,
    to destination: URL
) throws {
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
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

private func solidImage(color: NSColor, width: Int, height: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}

private func imageProperties(at url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    return (
        try #require(properties[kCGImagePropertyPixelWidth] as? Int),
        try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    )
}

private func containsPixel(
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
