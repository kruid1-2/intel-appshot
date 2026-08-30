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
    let destination = directory.appendingPathComponent("music-window.png")
    defer { try? FileManager.default.removeItem(at: directory) }

    try WindowScreenshotPNGWriter.write(image: image, to: destination)

    let data = try Data(contentsOf: destination)
    #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    #expect(data.count > 50)
}
