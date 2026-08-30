import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WindowScreenshotPNGWriterError: Error {
    case destinationCreationFailed
    case pngEncodingFailed
}

enum WindowScreenshotPNGWriter {
    static func write(image: CGImage, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw WindowScreenshotPNGWriterError.destinationCreationFailed
        }
        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw WindowScreenshotPNGWriterError.pngEncodingFailed
        }
    }
}
