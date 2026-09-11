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
    let contentFrameInPixels: CGRect?
}

@MainActor
public final class AppshotMagicMoveController {
    private static let shadowRadius: CGFloat = 18
    private static let shadowOffset = CGSize(width: 0, height: -5)
    // Original ARM: appshotShutterFadeIn (easeInOut, 0.15), followed by
    // appshotShutterFadeOut / appshotSnapshotFadeIn (easeIn, default 0.125).
    private static let shutterFadeInDuration: Double = 0.15
    private static let snapshotTakeoverDuration: Double = 0.125
    // Leave transparent pixels beyond the shadow's visible raster support.
    private static var shadowPadding: CGFloat {
        ceil(3 * shadowRadius + max(abs(shadowOffset.width), abs(shadowOffset.height)))
    }
    public private(set) var transitionSnapshot: AppshotTransitionSnapshotArtifact
    public let spring: AppshotMagicMoveSpring
    public let sourceFrame: CGRect
    public let destinationFrame: CGRect

    private let overlayWindow: AppshotMagicMoveOverlayWindow
    private let rootLayer: CALayer
    private let snapshotEffectsLayer: CALayer
    private let snapshotMaskLayer: CAGradientLayer
    private let cardLayer: CALayer
    private let screenshotLayer: CALayer
    private let shutterLayer: CALayer
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
    private var activationTask: Task<Void, Never>?
    private var activationRequestID = "unstarted"

    public static func prepare(
        screenshotURL: URL,
        sourceFrame: CGRect,
        applicationIcon: NSImage,
        title: String,
        animationTarget: AppshotAnimationTarget,
        transitionSnapshotURL: URL,
        primaryDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height,
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
        preservesExteriorShadow: Bool = false,
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
            preservesExteriorShadow: preservesExteriorShadow,
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
        preservesExteriorShadow: Bool,
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
        ).insetBy(dx: -Self.shadowPadding, dy: -Self.shadowPadding)
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

        // Mask the image, backing and shadow together. Accessories remain siblings
        // so the exported terminal PNG keeps its icon and title fully legible.
        snapshotEffectsLayer = CALayer()
        snapshotEffectsLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(snapshotEffectsLayer)
        snapshotMaskLayer = CAGradientLayer()
        snapshotMaskLayer.frame = rootLayer.bounds
        snapshotMaskLayer.contentsScale = animationTarget.displayScaleFactor
        snapshotMaskLayer.locations = [0, 0.5, 0.75, 0.95, 1]
        snapshotEffectsLayer.mask = snapshotMaskLayer

        cardLayer = CALayer()
        // Fixed shadow container: derive the shadow from the screenshot's alpha,
        // not an opaque rectangle. render(in:) also preserves this child shadow.
        cardLayer.frame = rootLayer.bounds
        cardLayer.masksToBounds = false
        cardLayer.shadowColor = NSColor.black.cgColor
        cardLayer.shadowOpacity = 0.22
        cardLayer.shadowRadius = Self.shadowRadius
        cardLayer.shadowOffset = Self.shadowOffset
        snapshotEffectsLayer.addSublayer(cardLayer)

        screenshotLayer = CALayer()
        screenshotLayer.contents = screenshotImage
        screenshotLayer.contentsGravity = .resizeAspect
        screenshotLayer.masksToBounds = true
        screenshotLayer.contentsScale = animationTarget.displayScaleFactor
        cardLayer.addSublayer(screenshotLayer)

        shutterLayer = CALayer()
        shutterLayer.name = "appshot.shutter"
        shutterLayer.backgroundColor = NSColor.white.cgColor
        shutterLayer.masksToBounds = true
        rootLayer.addSublayer(shutterLayer)

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

        // A solid destination-colored backing leaks through aspect-fit margins
        // and the screenshot's antialiased edges. Cast only a shadow, no fill.
        cardLayer.backgroundColor = nil

        Self.withoutImplicitAnimations {
            self.configureInitialState()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        configureTerminalState()
        let terminalPixels: AppshotTransitionSnapshotPixels
        do {
            terminalPixels = try Self.renderTerminalSnapshotPixels(
                rootLayer: rootLayer,
                contentFrame: destinationOuterFrame,
                preservesExteriorShadow: preservesExteriorShadow,
                displayScaleFactor: animationTarget.displayScaleFactor
            )
        } catch {
            configureInitialState()
            CATransaction.commit()
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
        // Preparation has no visible side effects. The source pixels and terminal
        // artifact are ready before a separate foreground gate permits presentation.
        transitionSnapshot = try transitionSnapshotWork.wait()
    }

    public func startWhenHostIsReady(_ host: AppshotHostActivation?, requestID: String) {
        guard activationTask == nil, !animationHasStarted, !didClose else { return }
        activationRequestID = UUID(uuidString: requestID)?.uuidString ?? "non-uuid"
        guard let host else {
            AppshotActivationLog.logger.info("activation-unavailable; retaining screenshot-only handoff")
            cancel()
            return
        }
        activationTask = Task { @MainActor [weak self] in
            guard let self, !self.didClose, !Task.isCancelled else { return }
            await self.presentShutter()
            guard !self.didClose, !Task.isCancelled else { return }
            let result = await host.waitUntilFrontmost()
            guard !self.didClose, !Task.isCancelled else { return }
            self.activationTask = nil
            guard result == .ready, host.isFrontmost() else {
                AppshotActivationLog.logger.info("activation-fallback result=\(result.rawValue, privacy: .public)")
                self.cancel()
                return
            }
            AppshotActivationLog.logger.info("host-frontmost request=\(self.activationRequestID, privacy: .public)")
            self.startAnimation()
        }
    }

    private func presentShutter() async {
        AppshotCaptureSound.shared.playIfEnabled()
        // Composer may activate independently while the flash is rising. Keep
        // an exact source-aligned replica under it, so that switch cannot expose
        // a different app through a partially transparent shutter. No flight yet.
        Self.withoutImplicitAnimations { snapshotEffectsLayer.opacity = 1 }
        overlayWindow.orderFrontRegardless()
        overlayWindow.displayIfNeeded()
        CATransaction.flush()
        AppshotActivationLog.logger.info("shutter-shown request=\(self.activationRequestID, privacy: .public)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { continuation.resume() }
            shutterLayer.opacity = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Self.shutterFadeInDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shutterLayer.add(fade, forKey: "appshotShutterFadeIn")
            CATransaction.commit()
        }
        AppshotActivationLog.logger.info("shutter-peak request=\(self.activationRequestID, privacy: .public)")
    }

    public func markComposerHandoffFinished() {
        AppshotActivationLog.logger.info("composer-handoff request=\(self.activationRequestID, privacy: .public)")
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
            to: screenshotLayer,
            from: sourceCardFrame,
            to: destinationCardFrame
        )
        addFrameAnimations(to: shutterLayer, from: sourceCardFrame, to: destinationCardFrame)
        // These animations and geometry start in the same transaction, on the
        // same persistent layers. There is no overlay replacement at the cut.
        let shutterFade = CABasicAnimation(keyPath: "opacity")
        shutterFade.fromValue = 1
        shutterFade.toValue = 0
        shutterFade.duration = Self.snapshotTakeoverDuration
        shutterFade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shutterLayer.add(shutterFade, forKey: "appshotShutterFadeOut")
        let snapshotFade = CABasicAnimation(keyPath: "opacity")
        snapshotFade.fromValue = 0
        snapshotFade.toValue = 1
        snapshotFade.duration = Self.snapshotTakeoverDuration
        snapshotFade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        snapshotEffectsLayer.add(snapshotFade, forKey: "appshotSnapshotFadeIn")

        // The final mask is already set under the opaque shutter. Only its
        // coordinates follow the screenshot; do not animate the fade's formation.
        for (keyPath, isTop) in [("startPoint", true), ("endPoint", false)] {
            addSpringAnimation(
                to: snapshotMaskLayer,
                keyPath: keyPath,
                fromValue: NSValue(point: maskPoint(for: sourceCardFrame, isTop: isTop)),
                toValue: NSValue(point: maskPoint(for: destinationCardFrame, isTop: isTop))
            )
        }

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
        AppshotActivationLog.logger.info("magic-move-committed request=\(self.activationRequestID, privacy: .public)")
    }

    private func animationDidFinish() {
        guard !didClose else { return }
        if lifecycle.markAnimationFinished() {
            closeOverlay()
        }
    }

    private func configureInitialState() {
        snapshotEffectsLayer.opacity = 0
        // During shutter, only the source pixels cover the real window. Its
        // existing system shadow must not be doubled by the destination backing.
        cardLayer.shadowOpacity = 0
        Self.setFrame(sourceCardFrame, on: shutterLayer)
        shutterLayer.cornerRadius = 10
        shutterLayer.opacity = 0
        configureSnapshotMask(for: sourceCardFrame, faded: false)
        Self.setFrame(sourceCardFrame, on: screenshotLayer)
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
        snapshotEffectsLayer.opacity = 1
        cardLayer.shadowOpacity = 0.22
        Self.setFrame(destinationCardFrame, on: shutterLayer)
        shutterLayer.cornerRadius = destinationCornerRadius
        shutterLayer.opacity = 0
        configureSnapshotMask(for: destinationCardFrame, faded: true)
        Self.setFrame(destinationCardFrame, on: screenshotLayer)
        screenshotLayer.cornerRadius = destinationCornerRadius

        let iconSize = AppshotTransitionSnapshotRenderer.iconSize * destinationScale
        iconLayer.bounds = CGRect(origin: .zero, size: CGSize(width: iconSize, height: iconSize))
        iconLayer.position = accessoryPosition(for: destinationCardFrame)
        iconLayer.opacity = 1

        configureTitleBounds()
        titleLayer.position = titlePosition(for: destinationCardFrame)
        titleLayer.opacity = 1
    }

    private func maskColors(faded: Bool) -> [CGColor] {
        // Original-style lower-half fade, not a claim of pixel-exact ARM stops.
        let alphas: [CGFloat] = faded ? [1, 1, 0.5, 0, 0] : [1, 1, 1, 1, 1]
        return alphas.map { CGColor(gray: 1, alpha: $0) }
    }

    private func maskPoint(for frame: CGRect, isTop: Bool) -> CGPoint {
        CGPoint(x: 0.5, y: (isTop ? frame.maxY : frame.minY) / rootLayer.bounds.height)
    }

    private func configureSnapshotMask(for frame: CGRect, faded: Bool) {
        // A full-overlay mask preserves top/side shadow support. The gradient
        // extends transparent below the body instead of exposing an unmasked shadow.
        snapshotMaskLayer.startPoint = maskPoint(for: frame, isTop: true)
        snapshotMaskLayer.endPoint = maskPoint(for: frame, isTop: false)
        snapshotMaskLayer.colors = maskColors(faded: faded)
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
        activationTask?.cancel()
        activationTask = nil
        rootLayer.removeAllAnimations()
        snapshotEffectsLayer.removeAllAnimations()
        shutterLayer.removeAllAnimations()
        snapshotMaskLayer.removeAllAnimations()
        cardLayer.removeAllAnimations()
        screenshotLayer.removeAllAnimations()
        iconLayer.removeAllAnimations()
        titleLayer.removeAllAnimations()
        overlayWindow.orderOut(nil)
        AppshotActivationLog.logger.info("overlay-closed request=\(self.activationRequestID, privacy: .public)")
        closeHandler?()
    }

    private static func renderTerminalSnapshotPixels(
        rootLayer: CALayer,
        contentFrame: CGRect,
        preservesExteriorShadow: Bool,
        displayScaleFactor: Double
    ) throws -> AppshotTransitionSnapshotPixels {
        let padding = preservesExteriorShadow ? shadowPadding : 0
        let cropFrame = contentFrame.insetBy(dx: -padding, dy: -padding)
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
            transitionSnapshotHeight: contentFrame.height,
            contentFrameInPixels: preservesExteriorShadow ? CGRect(
                x: (contentFrame.minX - cropFrame.minX) * displayScaleFactor,
                // The PNG has a top-left origin. Account for pixel-height rounding
                // here so fractional display/UI scales do not introduce a half-pixel jump.
                y: CGFloat(pixelsHigh) - (contentFrame.maxY - cropFrame.minY) * displayScaleFactor,
                width: contentFrame.width * displayScaleFactor,
                height: contentFrame.height * displayScaleFactor
            ) : nil
        )
    }

    nonisolated private static func writeTerminalSnapshot(
        _ pixels: AppshotTransitionSnapshotPixels,
        destinationURL: URL
    ) throws -> AppshotTransitionSnapshotArtifact {
        let description = try pixels.contentFrameInPixels.map { frame in
            let layout = try JSONSerialization.data(withJSONObject: [
                "x": frame.minX, "y": frame.minY,
                "width": frame.width, "height": frame.height
            ], options: [.sortedKeys])
            return "codex-appshot-layout-v1:" + String(decoding: layout, as: UTF8.self)
        }
        try WindowScreenshotPNGWriter.write(
            image: pixels.image,
            to: destinationURL,
            pngDescription: description
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
    private let preservesExteriorShadow: Bool

    public init(preservesExteriorShadow: Bool = false) {
        self.preservesExteriorShadow = preservesExteriorShadow
    }

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
            preservesExteriorShadow: preservesExteriorShadow,
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
