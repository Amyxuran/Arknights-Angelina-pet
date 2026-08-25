import Foundation
import Testing
@testable import LimeCourier

@Suite("Desktop pet behavior")
struct PetBehaviorTests {
    @Test("Horizontal drag direction selects the matching riding mirror")
    func dragDirectionMirror() {
        #expect(PetDragDirectionPolicy.shouldMirror(horizontalDelta: -4, currentMirrored: false))
        #expect(!PetDragDirectionPolicy.shouldMirror(horizontalDelta: 4, currentMirrored: true))
        #expect(PetDragDirectionPolicy.shouldMirror(horizontalDelta: 0, currentMirrored: true))
        #expect(!PetDragDirectionPolicy.shouldMirror(horizontalDelta: 0, currentMirrored: false))
    }

    @Test("Release inside 42 points snaps to every screen edge")
    func edgeSnap() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let size = CGSize(width: 168, height: 168)
        #expect(DesktopPlacement.snappedOrigin(CGPoint(x: 30, y: 400), size: size, visibleFrame: visible) == CGPoint(x: 0, y: 400))
        #expect(DesktopPlacement.snappedOrigin(CGPoint(x: 1240, y: 700), size: size, visibleFrame: visible) == CGPoint(x: 1272, y: 732))
        #expect(DesktopPlacement.snappedOrigin(CGPoint(x: 300, y: 300), size: size, visibleFrame: visible) == CGPoint(x: 300, y: 300))
    }

    @Test("Edge delivery preserves left and mirrors right")
    func edgeDeliveryMirror() {
        #expect(!PetBehaviorPolicy.edgeDeliveryShouldMirror(for: .left))
        #expect(PetBehaviorPolicy.edgeDeliveryShouldMirror(for: .right))
    }

    @Test("Edge bubble uses a five-to-one contact plane and four point icon insets")
    func bubbleFrame() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let full = CGRect(x: 0, y: 300, width: 168, height: 168)
        let left = PetBehaviorPolicy.bubbleFrame(edge: .left, fullPetFrame: full, visibleFrame: visible)
        let right = PetBehaviorPolicy.bubbleFrame(edge: .right, fullPetFrame: full, visibleFrame: visible)
        #expect(left == CGRect(x: 0, y: 278, width: 56, height: 212))
        #expect(right == CGRect(x: 1384, y: 278, width: 56, height: 212))
        #expect(PetInteractionConfiguration.bubbleVisualWidth == 48)
        #expect(PetInteractionConfiguration.bubbleIconWidth == 40)
        #expect(PetInteractionConfiguration.bubbleIconHeight == 40)
        #expect(PetInteractionConfiguration.bubbleIconHorizontalInset == 4)
        #expect(
            abs(
                PetInteractionConfiguration.bubbleContactHeight
                    / PetInteractionConfiguration.bubbleIconHeight - 5
            ) < 0.0001
        )
        #expect(PetInteractionConfiguration.bubbleContactTangentLength > 0)
        #expect(PetInteractionConfiguration.bubbleBodyHalfHeight > 0)
        #expect(
            PetInteractionConfiguration.bubbleVisualWidth
                - PetInteractionConfiguration.bubbleBodyJoinOffset
                == PetInteractionConfiguration.bubbleBodyHalfHeight
        )
        #expect(PetInteractionConfiguration.bubbleJoinAngleDegrees == 25)
        #expect(
            abs(PetInteractionConfiguration.bubbleArcSweepRadians * 180 / .pi - 65) < 0.0001
        )
        #expect(
            abs(
                PetInteractionConfiguration.bubbleJoinTangentLength
                    - PetInteractionConfiguration.bubbleArcControlFactor
                        * PetInteractionConfiguration.bubbleBodyHalfHeight
            ) < 0.0001
        )
        #expect(PetInteractionConfiguration.bubbleJoinTangentLength > 0)
        #expect(
            PetInteractionConfiguration.bubbleVisualWidth
                - PetInteractionConfiguration.bubbleIconWidth
                - PetInteractionConfiguration.bubbleIconHorizontalInset == 4
        )
    }

    @Test("Interaction timing matches the desktop behavior contract")
    func interactionTiming() {
        #expect(PetInteractionConfiguration.hoverDelay == 0.6)
        #expect(PetInteractionConfiguration.directInteractionRepeatCount == 3)
        #expect(PetInteractionConfiguration.longPressDelay == 0.8)
        #expect(PetInteractionConfiguration.cursorFollowStationaryDelay == 1)
        #expect(PetInteractionConfiguration.cursorFollowSpeed == 150)
        #expect(PetInteractionConfiguration.edgeDeliveryDelay == 1)
        #expect(PetInteractionConfiguration.bubbleAbsorptionDuration == 0.30)
    }

    @Test("Bubble suction curve starts and ends at rest and remains monotonic")
    func bubbleSuctionCurve() {
        #expect(PetBehaviorPolicy.bubbleSuctionProgress(0) == 0)
        #expect(PetBehaviorPolicy.bubbleSuctionProgress(1) == 1)
        let samples = stride(from: CGFloat(0), through: 1, by: 0.05)
            .map(PetBehaviorPolicy.bubbleSuctionProgress)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        let midpoint = PetBehaviorPolicy.bubbleSuctionProgress(0.5)
        #expect(midpoint > 0.49)
        #expect(midpoint < 0.51)
    }

    @Test("Standby selection exposes every animation asset")
    func standbyActions() {
        #expect(PetSelectableAction.allCases.map(\.rawValue) == [
            "坐坐", "拍照", "探险", "海边", "潜水",
            "看书", "纸飞机", "购物", "送货", "骑行"
        ])
    }

    @Test("Cursor follow accepts any distance and stops 56 points away")
    func cursorFollow() {
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let frame = CGRect(x: 100, y: 100, width: 100, height: 100)
        let target = PetBehaviorPolicy.cursorFollowOrigin(
            petFrame: frame,
            cursor: CGPoint(x: 950, y: 150),
            visibleFrame: visible
        )
        #expect(target == CGPoint(x: 844, y: 100))
    }
}
