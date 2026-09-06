import CoreGraphics
import Foundation
import Testing
@testable import AppshotShimCore

@Test("magic move uses the recovered distance response and damping constants")
func magicMoveSpringMatchesRecoveredFormula() {
    let source = CGRect(x: 0, y: 0, width: 800, height: 600)
    let destination = CGRect(x: 1_000, y: 500, width: 232, height: 140)
    let centerDistance = hypot(
        source.midX - destination.midX,
        source.midY - destination.midY
    )
    let expectedResponse = 0.57
        - 0.29 * exp(-0.00035546009259484373 * centerDistance)

    let spring = AppshotMagicMoveSpring.frames(
        sourceFrame: source,
        destinationFrame: destination
    )

    #expect(abs(spring.response - expectedResponse) < 0.000_000_001)
    #expect(spring.dampingFraction == 0.73)
    #expect(abs(spring.animationDuration - (3 * expectedResponse + 0.15)) < 0.000_000_001)
}

@Test("zero-distance magic move has the recovered minimum response")
func zeroDistanceMagicMoveUsesMinimumResponse() {
    let frame = CGRect(x: 20, y: 30, width: 232, height: 140)

    let spring = AppshotMagicMoveSpring.frames(
        sourceFrame: frame,
        destinationFrame: frame
    )

    #expect(abs(spring.response - 0.28) < 0.000_000_001)
    #expect(abs(spring.animationDuration - 0.99) < 0.000_000_001)
}

@Test("Core Animation spring preserves the recovered response and damping rhythm")
func coreAnimationSpringUsesRecoveredPhysicalParameters() {
    let spring = AppshotMagicMoveSpring(
        response: 0.43,
        dampingFraction: 0.73,
        animationDuration: 1.44
    )
    let parameters = spring.coreAnimationParameters
    let angularFrequency = 2 * Double.pi / spring.response

    #expect(parameters.mass == 1)
    #expect(abs(parameters.stiffness - angularFrequency * angularFrequency) < 0.000_000_001)
    #expect(
        abs(parameters.damping - 2 * spring.dampingFraction * angularFrequency)
            < 0.000_000_001
    )
    #expect(parameters.initialVelocity == 0)
    #expect(parameters.duration == spring.animationDuration)
}

@Test("fixed overlay contains the entire source-to-destination flight")
func fixedOverlayGeometryContainsBothEndpoints() {
    let source = CGRect(x: 100, y: 240, width: 900, height: 600)
    let destinationOuter = CGRect(x: 1_100, y: 80, width: 232, height: 161)

    let overlay = AppshotMagicMoveGeometry.fixedOverlayFrame(
        sourceFrame: source,
        destinationOuterFrame: destinationOuter
    )

    #expect(overlay == source.union(destinationOuter))
    #expect(
        AppshotMagicMoveGeometry.localFrame(source, in: overlay)
            == CGRect(x: 0, y: 160, width: 900, height: 600)
    )
    #expect(
        AppshotMagicMoveGeometry.localFrame(destinationOuter, in: overlay)
            == CGRect(x: 1_000, y: 0, width: 232, height: 161)
    )
}

@Test("overlay closes only after both animation and Composer final handoff")
func magicMoveLifecycleRequiresBothGates() {
    var animationFirst = AppshotMagicMoveLifecycle()
    let animationFirstClose = animationFirst.markAnimationFinished()
    #expect(!animationFirstClose)
    #expect(!animationFirst.isClosed)
    let animationFirstHandoffClose = animationFirst.markComposerHandoffFinished()
    #expect(animationFirstHandoffClose)
    #expect(animationFirst.isClosed)
    let duplicateAnimationFirstClose = animationFirst.markComposerHandoffFinished()
    #expect(!duplicateAnimationFirstClose)

    var composerFirst = AppshotMagicMoveLifecycle()
    let composerFirstClose = composerFirst.markComposerHandoffFinished()
    #expect(!composerFirstClose)
    #expect(!composerFirst.isClosed)
    let composerFirstAnimationClose = composerFirst.markAnimationFinished()
    #expect(composerFirstAnimationClose)
    #expect(composerFirst.isClosed)
    let duplicateComposerFirstClose = composerFirst.markAnimationFinished()
    #expect(!duplicateComposerFirstClose)
}
