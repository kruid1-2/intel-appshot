import AppKit
import Foundation

public enum AppshotTransitionSnapshotRendererError: Error {
    case invalidAnimationTarget
    case screenshotUnavailable
    case bitmapCreationFailed
    case pngEncodingFailed
    case screenshotAndTransitionPathsMatch
}

public struct AppshotTransitionSnapshotArtifact: Equatable, Sendable {
    public let url: URL
    public let transitionSnapshotHeight: Double

    public init(url: URL, transitionSnapshotHeight: Double) {
        self.url = url
        self.transitionSnapshotHeight = transitionSnapshotHeight
    }
}

public enum AppshotTransitionSnapshotRenderer {
    public static let logicalWidth = 232.0
    public static let screenshotHeight = 140.0
    public static let titleGap = 4.0
    public static let titleLineHeight = 17.0
    public static let logicalHeight = 161.0
    public static let iconSize = 24.0

    @MainActor
    public static func render(
        screenshotURL: URL,
        applicationIcon: NSImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        destinationURL: URL
    ) throws -> AppshotTransitionSnapshotArtifact {
        guard screenshotURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            throw AppshotTransitionSnapshotRendererError.screenshotAndTransitionPathsMatch
        }
        let transitionScale = animationTarget.destinationFrameWidth / logicalWidth
        let displayScaleFactor = animationTarget.displayScaleFactor
        guard
            transitionScale.isFinite,
            transitionScale > 0,
            displayScaleFactor.isFinite,
            displayScaleFactor > 0
        else {
            throw AppshotTransitionSnapshotRendererError.invalidAnimationTarget
        }
        guard let screenshot = NSImage(contentsOf: screenshotURL),
              screenshot.size.width > 0,
              screenshot.size.height > 0 else {
            throw AppshotTransitionSnapshotRendererError.screenshotUnavailable
        }

        let rasterScale = transitionScale * displayScaleFactor
        let pixelsWide = Int((logicalWidth * rasterScale).rounded())
        let pixelsHigh = Int((logicalHeight * rasterScale).rounded())
        guard
            pixelsWide > 0,
            pixelsHigh > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw AppshotTransitionSnapshotRendererError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let context = graphicsContext.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        context.scaleBy(x: rasterScale, y: rasterScale)
        context.interpolationQuality = .high

        let screenshotScale = min(
            logicalWidth / screenshot.size.width,
            screenshotHeight / screenshot.size.height
        )
        let renderedScreenshotSize = NSSize(
            width: screenshot.size.width * screenshotScale,
            height: screenshot.size.height * screenshotScale
        )
        let screenshotOriginY = titleLineHeight + titleGap
        let screenshotRect = NSRect(
            x: (logicalWidth - renderedScreenshotSize.width) / 2,
            y: screenshotOriginY,
            width: renderedScreenshotSize.width,
            height: renderedScreenshotSize.height
        )
        screenshot.draw(
            in: screenshotRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        let iconRect = NSRect(
            x: (logicalWidth - iconSize) / 2,
            y: screenshotOriginY,
            width: iconSize,
            height: iconSize
        )
        applicationIcon.draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let color = animationTarget.destinationPrimaryTextColor
            .map(nsColor(from:))
            ?? NSColor.labelColor
        (title as NSString).draw(
            with: NSRect(x: 8, y: 0, width: logicalWidth - 16, height: titleLineHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
        graphicsContext.flushGraphics()

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppshotTransitionSnapshotRendererError.pngEncodingFailed
        }
        try png.write(to: destinationURL, options: .atomic)

        return AppshotTransitionSnapshotArtifact(
            url: destinationURL,
            transitionSnapshotHeight: logicalHeight * transitionScale
        )
    }

    private static func nsColor(from color: AppshotRGBColor) -> NSColor {
        NSColor(
            calibratedRed: min(255, max(0, color.red)) / 255,
            green: min(255, max(0, color.green)) / 255,
            blue: min(255, max(0, color.blue)) / 255,
            alpha: 1
        )
    }
}
