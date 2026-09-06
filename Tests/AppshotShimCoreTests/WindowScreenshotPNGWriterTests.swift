import CoreGraphics
import Foundation
import Testing
@testable import AppshotShimCore

@Test("window screenshot writer encodes a CGImage as PNG")
func windowScreenshotWriterEncodesPNG() throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(
        CGContext(
            data: nil,
            width: 8,
            height: 6,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
    let image = try #require(context.makeImage())
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let destination = directory.appendingPathComponent("frontmost-window.png")
    defer { try? FileManager.default.removeItem(at: directory) }

    try WindowScreenshotPNGWriter.write(image: image, to: destination)

    let data = try Data(contentsOf: destination)
    #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    #expect(data.count > 50)
}

@Test("captured window image can be persisted after the in-memory capture exists")
func capturedWindowImagePersistsLater() throws {
    let image = try #require(solidScreenshotImage(width: 8, height: 6))
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let destination = directory.appendingPathComponent("frontmost-window.png")
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = FrontmostWindowImageCapture(
        image: image,
        windowID: 42,
        windowFrame: CGRect(x: 10, y: 20, width: 320, height: 200),
        mappingMethod: "test",
        mappingDurationMilliseconds: 2,
        shareableContentDurationMilliseconds: 3,
        imageCaptureDurationMilliseconds: 4,
        totalDurationMilliseconds: 9
    )

    #expect(!FileManager.default.fileExists(atPath: destination.path))

    let screenshot = try capture.writePNG(to: destination)

    #expect(FileManager.default.fileExists(atPath: destination.path))
    #expect(screenshot.screenshotURL == destination)
    #expect(screenshot.windowID == 42)
    #expect(screenshot.windowFrame == CGRect(x: 10, y: 20, width: 320, height: 200))
}

private func solidScreenshotImage(width: Int, height: Int) -> CGImage? {
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
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
