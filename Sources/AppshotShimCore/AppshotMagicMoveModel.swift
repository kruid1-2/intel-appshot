import CoreGraphics
import Foundation

public struct AppshotMagicMoveSpring: Equatable, Sendable {
    public static let dampingFraction = 0.73

    public let response: Double
    public let dampingFraction: Double
    public let animationDuration: Double

    public static func frames(
        sourceFrame: CGRect,
        destinationFrame: CGRect
    ) -> Self {
        let distance = hypot(
            sourceFrame.midX - destinationFrame.midX,
            sourceFrame.midY - destinationFrame.midY
        )
        let response = 0.57
            - 0.29 * exp(-0.00035546009259484373 * distance)
        return Self(
            response: response,
            dampingFraction: dampingFraction,
            animationDuration: 3 * response + 0.15
        )
    }

    public func progress(at elapsedTime: TimeInterval) -> Double {
        guard elapsedTime > 0 else { return 0 }
        guard elapsedTime < animationDuration else { return 1 }

        let damping = min(max(dampingFraction, 0.000_001), 0.999_999)
        let angularFrequency = 2 * Double.pi / response
        let dampedFrequency = angularFrequency * sqrt(1 - damping * damping)
        let decay = exp(-damping * angularFrequency * elapsedTime)
        let phase = cos(dampedFrequency * elapsedTime)
            + damping / sqrt(1 - damping * damping)
                * sin(dampedFrequency * elapsedTime)
        return 1 - decay * phase
    }

    public var coreAnimationParameters: AppshotMagicMoveCoreAnimationSpring {
        let angularFrequency = 2 * Double.pi / response
        return AppshotMagicMoveCoreAnimationSpring(
            mass: 1,
            stiffness: angularFrequency * angularFrequency,
            damping: 2 * dampingFraction * angularFrequency,
            initialVelocity: 0,
            duration: animationDuration
        )
    }
}

public struct AppshotMagicMoveCoreAnimationSpring: Equatable, Sendable {
    public let mass: Double
    public let stiffness: Double
    public let damping: Double
    public let initialVelocity: Double
    public let duration: Double
}

public enum AppshotMagicMoveGeometry {
    public static func appKitFrame(
        fromTopLeftScreenFrame frame: CGRect,
        primaryDisplayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryDisplayHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func interpolate(
        from source: CGRect,
        to destination: CGRect,
        progress: Double
    ) -> CGRect {
        let progress = CGFloat(progress)
        return CGRect(
            x: source.origin.x + (destination.origin.x - source.origin.x) * progress,
            y: source.origin.y + (destination.origin.y - source.origin.y) * progress,
            width: source.width + (destination.width - source.width) * progress,
            height: source.height + (destination.height - source.height) * progress
        )
    }

    public static func fixedOverlayFrame(
        sourceFrame: CGRect,
        destinationOuterFrame: CGRect
    ) -> CGRect {
        sourceFrame.union(destinationOuterFrame)
    }

    public static func localFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: frame.minX - container.minX,
            y: frame.minY - container.minY,
            width: frame.width,
            height: frame.height
        )
    }
}

public struct AppshotMagicMoveLifecycle: Equatable, Sendable {
    public private(set) var isClosed = false
    private var animationFinished = false
    private var composerHandoffFinished = false

    public init() {}

    @discardableResult
    public mutating func markAnimationFinished() -> Bool {
        guard !isClosed else { return false }
        animationFinished = true
        return closeIfReady()
    }

    @discardableResult
    public mutating func markComposerHandoffFinished() -> Bool {
        guard !isClosed else { return false }
        composerHandoffFinished = true
        return closeIfReady()
    }

    private mutating func closeIfReady() -> Bool {
        guard animationFinished, composerHandoffFinished else { return false }
        isClosed = true
        return true
    }
}
