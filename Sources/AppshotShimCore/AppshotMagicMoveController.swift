import AppKit
import Foundation
import ImageIO
import QuartzCore

public enum AppshotMagicMoveControllerError: Error {
    case invalidFrames
    case screenshotUnavailable
    case applicationIconUnavailable
    case bitmapCreationFailed
    case pngEncodingFailed
    case screenshotAndTransitionPathsMatch
}

final class AppshotMagicMoveOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none
        hidesOnDeactivate = false
        animationBehavior = .none
    }
}

private struct AppshotTransitionSnapshotPixels: @unchecked Sendable {
    let image: CGImage
    let transitionSnapshotHeight: Double
}

@MainActor
public final class AppshotMagicMoveController {
    public private(set) var transitionSnapshot: AppshotTransitionSnapshotArtifact
    public let spring: AppshotMagicMoveSpring
    public let sourceFrame: CGRect
    public let destinationFrame: CGRect

    private let overlayWindow: AppshotMagicMoveOverlayWindow
    private let rootLayer: CALayer
    private let cardLayer: CALayer
    private let screenshotLayer: CALayer
    private let iconLayer: CALayer
    private let titleLayer: CATextLayer
    private let sourceCardFrame: CGRect
    private let destinationCardFrame: CGRect
    private let destinationOuterFrame: CGRect
    private let destinationScale: CGFloat
    private let destinationCornerRadius: CGFloat
    private let closeHandler: (() -> Void)?
    private var lifecycle = AppshotMagicMoveLifecycle()
    private var animationHasStarted = false
    private var didClose = false

    public static func prepare(
        screenshotURL: URL,
        sourceFrame: CGRect,
        applicationIcon: NSImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL,
        primaryDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height,
        showOverlay: Bool = true,
        closeHandler: (() -> Void)? = nil
    ) throws -> AppshotMagicMoveController {
        guard screenshotURL.standardizedFileURL
            != transitionSnapshotURL.standardizedFileURL else {
            throw AppshotMagicMoveControllerError.screenshotAndTransitionPathsMatch
        }
        guard let imageSource = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
              let screenshotImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw AppshotMagicMoveControllerError.screenshotUnavailable
        }
        return try prepare(
            screenshotImage: screenshotImage,
            sourceFrame: sourceFrame,
            applicationIcon: applicationIcon,
            title: title,
            animationTarget: animationTarget,
            transitionSnapshotURL: transitionSnapshotURL,
            primaryDisplayHeight: primaryDisplayHeight,
            showOverlay: showOverlay,
            closeHandler: closeHandler
        )
    }

    public static func prepare(
        screenshotImage: CGImage,
        sourceFrame: CGRect,
        applicationIcon: NSImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL,
        primaryDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height,
        showOverlay: Bool = true,
        closeHandler: (() -> Void)? = nil
    ) throws -> AppshotMagicMoveController {
        var iconRect = CGRect(origin: .zero, size: applicationIcon.size)
        guard let applicationIconImage = applicationIcon.cgImage(
            forProposedRect: &iconRect,
            context: nil,
            hints: nil
        ) else {
            throw AppshotMagicMoveControllerError.applicationIconUnavailable
        }
        return try prepare(
            screenshotImage: screenshotImage,
            sourceFrame: sourceFrame,
            applicationIconImage: applicationIconImage,
            title: title,
            animationTarget: animationTarget,
            transitionSnapshotURL: transitionSnapshotURL,
            primaryDisplayHeight: primaryDisplayHeight,
            showOverlay: showOverlay,
            closeHandler: closeHandler
        )
    }

    public static func prepare(
        screenshotImage: CGImage,
        sourceFrame: CGRect,
        applicationIconImage: CGImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL,
        primaryDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height,
        showOverlay: Bool = true,
        closeHandler: (() -> Void)? = nil
    ) throws -> AppshotMagicMoveController {
        try AppshotMagicMoveController(
            screenshotImage: screenshotImage,
            sourceFrame: sourceFrame,
            applicationIconImage: applicationIconImage,
            title: title,
            animationTarget: animationTarget,
            transitionSnapshotURL: transitionSnapshotURL,
            primaryDisplayHeight: primaryDisplayHeight,
            showOverlay: showOverlay,
            closeHandler: closeHandler
        )
    }

    private init(
        screenshotImage: CGImage,
        sourceFrame: CGRect,
        applicationIconImage: CGImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL,
        primaryDisplayHeight: CGFloat,
        showOverlay: Bool,
        closeHandler: (() -> Void)?
    ) throws {
        let destinationFrame = animationTarget.destinationFrame
        guard Self.isValid(frame: sourceFrame), Self.isValid(frame: destinationFrame) else {
            throw AppshotMagicMoveControllerError.invalidFrames
        }

        self.sourceFrame = sourceFrame
        self.destinationFrame = destinationFrame
        transitionSnapshot = AppshotTransitionSnapshotArtifact(
            url: transitionSnapshotURL,
            transitionSnapshotHeight: 0
        )
        spring = .frames(sourceFrame: sourceFrame, destinationFrame: destinationFrame)
        destinationScale = destinationFrame.width
            / AppshotTransitionSnapshotRenderer.logicalWidth
        destinationCornerRadius = animationTarget.destinationCornerRadius
        self.closeHandler = closeHandler
        let sourceAppKitFrame = AppshotMagicMoveGeometry.appKitFrame(
            fromTopLeftScreenFrame: sourceFrame,
            primaryDisplayHeight: primaryDisplayHeight
        )
        let destinationAppKitFrame = AppshotMagicMoveGeometry.appKitFrame(
            fromTopLeftScreenFrame: destinationFrame,
            primaryDisplayHeight: primaryDisplayHeight
        )

        let titleAreaHeight = (
            AppshotTransitionSnapshotRenderer.titleGap
                + AppshotTransitionSnapshotRenderer.titleLineHeight
        ) * destinationScale
        let destinationOuterAppKitFrame = CGRect(
            x: destinationAppKitFrame.minX,
            y: destinationAppKitFrame.minY - titleAreaHeight,
            width: destinationAppKitFrame.width,
            height: destinationAppKitFrame.height + titleAreaHeight
        )
        let overlayFrame = AppshotMagicMoveGeometry.fixedOverlayFrame(
            sourceFrame: sourceAppKitFrame,
            destinationOuterFrame: destinationOuterAppKitFrame
        )
        sourceCardFrame = AppshotMagicMoveGeometry.localFrame(
            sourceAppKitFrame,
            in: overlayFrame
        )
        destinationCardFrame = AppshotMagicMoveGeometry.localFrame(
            destinationAppKitFrame,
            in: overlayFrame
        )
        destinationOuterFrame = AppshotMagicMoveGeometry.localFrame(
            destinationOuterAppKitFrame,
            in: overlayFrame
        )
        overlayWindow = AppshotMagicMoveOverlayWindow(contentRect: overlayFrame)

        let contentView = NSView(
            frame: CGRect(origin: .zero, size: overlayFrame.size)
        )
        contentView.wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.frame = contentView.bounds
        rootLayer.contentsScale = animationTarget.displayScaleFactor
        contentView.layer = rootLayer
        overlayWindow.contentView = contentView
        self.rootLayer = rootLayer

        cardLayer = CALayer()
        cardLayer.masksToBounds = false
        cardLayer.shadowColor = NSColor.black.cgColor
        cardLayer.shadowOpacity = 0.22
        cardLayer.shadowRadius = 18
        cardLayer.shadowOffset = CGSize(width: 0, height: -5)
        rootLayer.addSublayer(cardLayer)

        screenshotLayer = CALayer()
        screenshotLayer.contents = screenshotImage
        screenshotLayer.contentsGravity = .resizeAspect
        screenshotLayer.masksToBounds = true
        screenshotLayer.contentsScale = animationTarget.displayScaleFactor
        rootLayer.addSublayer(screenshotLayer)

        iconLayer = CALayer()
        iconLayer.contents = applicationIconImage
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.contentsScale = animationTarget.displayScaleFactor
        rootLayer.addSublayer(iconLayer)

        titleLayer = CATextLayer()
        titleLayer.string = title
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .end
        titleLayer.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLayer.fontSize = 13 * destinationScale
        titleLayer.foregroundColor = Self.cgColor(
            animationTarget.destinationPrimaryTextColor,
            fallback: .labelColor
        )
        titleLayer.contentsScale = animationTarget.displayScaleFactor
        titleLayer.needsDisplayOnBoundsChange = false
        rootLayer.addSublayer(titleLayer)

        let backgroundColor = Self.cgColor(
            animationTarget.destinationBackgroundColor,
            fallback: .clear
        )
        cardLayer.backgroundColor = backgroundColor

        Self.withoutImplicitAnimations {
            self.configureInitialState()
        }

        if showOverlay {
            overlayWindow.orderFrontRegardless()
            overlayWindow.displayIfNeeded()
            CATransaction.flush()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        configureTerminalState()
        let terminalPixels: AppshotTransitionSnapshotPixels
        do {
            terminalPixels = try Self.renderTerminalSnapshotPixels(
                rootLayer: rootLayer,
                cropFrame: destinationOuterFrame,
                displayScaleFactor: animationTarget.displayScaleFactor
            )
        } catch {
            configureInitialState()
            CATransaction.commit()
            if showOverlay {
                overlayWindow.orderOut(nil)
            }
            throw error
        }
        configureInitialState()
        CATransaction.commit()

        let transitionSnapshotWork = AppshotBackgroundWork<AppshotTransitionSnapshotArtifact> {
            try Self.writeTerminalSnapshot(
                terminalPixels,
                destinationURL: transitionSnapshotURL
            )
        }
        if showOverlay {
            startAnimation()
        }
        do {
            transitionSnapshot = try transitionSnapshotWork.wait()
        } catch {
            if showOverlay {
                overlayWindow.orderOut(nil)
            }
            throw error
        }
    }

    public func markComposerHandoffFinished() {
        if lifecycle.markComposerHandoffFinished() {
            closeOverlay()
        }
    }

    public func cancel() {
        guard !lifecycle.isClosed else { return }
        closeOverlay()
    }

    private func startAnimation() {
        guard !animationHasStarted, !didClose else { return }
        animationHasStarted = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                self?.animationDidFinish()
            }
        }

        configureTerminalState()
        addFrameAnimations(
            to: cardLayer,
            from: sourceCardFrame,
            to: destinationCardFrame
        )
        addFrameAnimations(
            to: screenshotLayer,
            from: sourceCardFrame,
            to: destinationCardFrame
        )

        addSpringAnimation(
            to: iconLayer,
            keyPath: "position",
            fromValue: NSValue(point: accessoryPosition(for: sourceCardFrame)),
            toValue: NSValue(point: accessoryPosition(for: destinationCardFrame))
        )
        addSpringAnimation(
            to: titleLayer,
            keyPath: "position",
            fromValue: NSValue(point: titlePosition(for: sourceCardFrame)),
            toValue: NSValue(point: titlePosition(for: destinationCardFrame))
        )
        iconLayer.add(accessoryOpacityAnimation(), forKey: "magicMove.opacity")
        titleLayer.add(accessoryOpacityAnimation(), forKey: "magicMove.opacity")
        CATransaction.commit()
    }

    private func animationDidFinish() {
        guard !didClose else { return }
        if lifecycle.markAnimationFinished() {
            closeOverlay()
        }
    }

    private func configureInitialState() {
        Self.setFrame(sourceCardFrame, on: cardLayer)
        Self.setFrame(sourceCardFrame, on: screenshotLayer)
        cardLayer.cornerRadius = 10
        screenshotLayer.cornerRadius = 10

        let iconSize = AppshotTransitionSnapshotRenderer.iconSize * destinationScale
        iconLayer.bounds = CGRect(origin: .zero, size: CGSize(width: iconSize, height: iconSize))
        iconLayer.position = accessoryPosition(for: sourceCardFrame)
        iconLayer.opacity = 0

        configureTitleBounds()
        titleLayer.position = titlePosition(for: sourceCardFrame)
        titleLayer.opacity = 0
    }

    private func configureTerminalState() {
        Self.setFrame(destinationCardFrame, on: cardLayer)
        Self.setFrame(destinationCardFrame, on: screenshotLayer)
        cardLayer.cornerRadius = destinationCornerRadius
        screenshotLayer.cornerRadius = destinationCornerRadius

        let iconSize = AppshotTransitionSnapshotRenderer.iconSize * destinationScale
        iconLayer.bounds = CGRect(origin: .zero, size: CGSize(width: iconSize, height: iconSize))
        iconLayer.position = accessoryPosition(for: destinationCardFrame)
        iconLayer.opacity = 1

        configureTitleBounds()
        titleLayer.position = titlePosition(for: destinationCardFrame)
        titleLayer.opacity = 1
    }

    private func configureTitleBounds() {
        let titleHeight = AppshotTransitionSnapshotRenderer.titleLineHeight * destinationScale
        titleLayer.bounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: max(destinationCardFrame.width - 16 * destinationScale, 1),
                height: titleHeight
            )
        )
    }

    private func accessoryPosition(for cardFrame: CGRect) -> CGPoint {
        let iconSize = AppshotTransitionSnapshotRenderer.iconSize * destinationScale
        return CGPoint(x: cardFrame.midX, y: cardFrame.minY + iconSize / 2)
    }

    private func titlePosition(for cardFrame: CGRect) -> CGPoint {
        let titleGap = AppshotTransitionSnapshotRenderer.titleGap * destinationScale
        let titleHeight = AppshotTransitionSnapshotRenderer.titleLineHeight * destinationScale
        return CGPoint(
            x: cardFrame.midX,
            y: cardFrame.minY - titleGap - titleHeight / 2
        )
    }

    private func addFrameAnimations(
        to layer: CALayer,
        from source: CGRect,
        to destination: CGRect
    ) {
        addSpringAnimation(
            to: layer,
            keyPath: "position",
            fromValue: NSValue(point: CGPoint(x: source.midX, y: source.midY)),
            toValue: NSValue(point: CGPoint(x: destination.midX, y: destination.midY))
        )
        addSpringAnimation(
            to: layer,
            keyPath: "bounds.size",
            fromValue: NSValue(size: source.size),
            toValue: NSValue(size: destination.size)
        )
        addSpringAnimation(
            to: layer,
            keyPath: "cornerRadius",
            fromValue: 10,
            toValue: destinationCornerRadius
        )
    }

    private func addSpringAnimation(
        to layer: CALayer,
        keyPath: String,
        fromValue: Any,
        toValue: Any
    ) {
        let parameters = spring.coreAnimationParameters
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = parameters.mass
        animation.stiffness = parameters.stiffness
        animation.damping = parameters.damping
        animation.initialVelocity = parameters.initialVelocity
        animation.duration = parameters.duration
        animation.fromValue = fromValue
        animation.toValue = toValue
        layer.add(animation, forKey: "magicMove.\(keyPath)")
    }

    private func accessoryOpacityAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        let sampleCount = max(Int((spring.animationDuration * 120).rounded(.up)), 2)
        animation.values = (0...sampleCount).map { index in
            let elapsed = spring.animationDuration * Double(index) / Double(sampleCount)
            let progress = spring.progress(at: elapsed)
            return NSNumber(value: min(max((progress - 0.55) / 0.45, 0), 1))
        }
        animation.duration = spring.animationDuration
        animation.calculationMode = .linear
        return animation
    }

    private func closeOverlay() {
        guard !didClose else { return }
        didClose = true
        rootLayer.removeAllAnimations()
        cardLayer.removeAllAnimations()
        screenshotLayer.removeAllAnimations()
        iconLayer.removeAllAnimations()
        titleLayer.removeAllAnimations()
        overlayWindow.orderOut(nil)
        closeHandler?()
    }

    private static func renderTerminalSnapshotPixels(
        rootLayer: CALayer,
        cropFrame: CGRect,
        displayScaleFactor: Double
    ) throws -> AppshotTransitionSnapshotPixels {
        let pixelsWide = Int((cropFrame.width * displayScaleFactor).rounded())
        let pixelsHigh = Int((cropFrame.height * displayScaleFactor).rounded())
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
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw AppshotMagicMoveControllerError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let cgContext = context.cgContext
        cgContext.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        cgContext.scaleBy(x: displayScaleFactor, y: displayScaleFactor)
        cgContext.translateBy(x: -cropFrame.minX, y: -cropFrame.minY)
        rootLayer.render(in: cgContext)
        context.flushGraphics()
        guard let image = bitmap.cgImage else {
            throw AppshotMagicMoveControllerError.bitmapCreationFailed
        }
        return AppshotTransitionSnapshotPixels(
            image: image,
            transitionSnapshotHeight: cropFrame.height
        )
    }

    nonisolated private static func writeTerminalSnapshot(
        _ pixels: AppshotTransitionSnapshotPixels,
        destinationURL: URL
    ) throws -> AppshotTransitionSnapshotArtifact {
        try WindowScreenshotPNGWriter.write(
            image: pixels.image,
            to: destinationURL
        )
        return AppshotTransitionSnapshotArtifact(
            url: destinationURL,
            transitionSnapshotHeight: pixels.transitionSnapshotHeight
        )
    }

    private static func setFrame(_ frame: CGRect, on layer: CALayer) {
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func isValid(frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }

    private static func cgColor(
        _ color: AppshotRGBColor?,
        fallback: NSColor
    ) -> CGColor {
        guard let color else { return fallback.cgColor }
        return NSColor(
            calibratedRed: min(255, max(0, color.red)) / 255,
            green: min(255, max(0, color.green)) / 255,
            blue: min(255, max(0, color.blue)) / 255,
            alpha: 1
        ).cgColor
    }

    private static func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

@MainActor
public final class AppshotMagicMoveCoordinator {
    private var activeMoves: [String: AppshotMagicMoveController] = [:]

    public init() {}

    public func start(
        requestID: String,
        screenshotURL: URL,
        sourceFrame: CGRect,
        applicationIcon: NSImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL
    ) throws -> AppshotMagicMoveController {
        guard screenshotURL.standardizedFileURL
            != transitionSnapshotURL.standardizedFileURL else {
            throw AppshotMagicMoveControllerError.screenshotAndTransitionPathsMatch
        }
        guard let imageSource = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
              let screenshotImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw AppshotMagicMoveControllerError.screenshotUnavailable
        }
        return try start(
            requestID: requestID,
            screenshotImage: screenshotImage,
            sourceFrame: sourceFrame,
            applicationIcon: applicationIcon,
            title: title,
            animationTarget: animationTarget,
            transitionSnapshotURL: transitionSnapshotURL
        )
    }

    public func start(
        requestID: String,
        screenshotImage: CGImage,
        sourceFrame: CGRect,
        applicationIcon: NSImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL
    ) throws -> AppshotMagicMoveController {
        var iconRect = CGRect(origin: .zero, size: applicationIcon.size)
        guard let applicationIconImage = applicationIcon.cgImage(
            forProposedRect: &iconRect,
            context: nil,
            hints: nil
        ) else {
            throw AppshotMagicMoveControllerError.applicationIconUnavailable
        }
        return try start(
            requestID: requestID,
            screenshotImage: screenshotImage,
            sourceFrame: sourceFrame,
            applicationIconImage: applicationIconImage,
            title: title,
            animationTarget: animationTarget,
            transitionSnapshotURL: transitionSnapshotURL
        )
    }

    public func start(
        requestID: String,
        screenshotImage: CGImage,
        sourceFrame: CGRect,
        applicationIconImage: CGImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL
    ) throws -> AppshotMagicMoveController {
        let existingMoves = Array(activeMoves.values)
        activeMoves.removeAll()
        for existing in existingMoves {
            existing.cancel()
        }
        let move = try AppshotMagicMoveController.prepare(
            screenshotImage: screenshotImage,
            sourceFrame: sourceFrame,
            applicationIconImage: applicationIconImage,
            title: title,
            animationTarget: animationTarget,
            transitionSnapshotURL: transitionSnapshotURL,
            closeHandler: { [weak self] in
                self?.activeMoves.removeValue(forKey: requestID)
            }
        )
        activeMoves[requestID] = move
        return move
    }

    public func markComposerHandoffFinished(requestID: String) {
        activeMoves[requestID]?.markComposerHandoffFinished()
    }
}
