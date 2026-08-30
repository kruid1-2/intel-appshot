import AppKit
import Foundation

public enum ProbeScreenshotWriterError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
}

@MainActor
public enum ProbeScreenshotWriter {
    public static func write(to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 640,
            pixelsHigh: 360,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ProbeScreenshotWriterError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 640, height: 360).fill()

        let title = "Intel Appshot protocol probe" as NSString
        title.draw(
            at: NSPoint(x: 44, y: 188),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        let detail = "Static test image from the x86_64 compatibility service" as NSString
        detail.draw(
            at: NSPoint(x: 46, y: 142),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1)
            ]
        )
        context.flushGraphics()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ProbeScreenshotWriterError.pngEncodingFailed
        }
        try png.write(to: destination, options: .atomic)
    }
}
