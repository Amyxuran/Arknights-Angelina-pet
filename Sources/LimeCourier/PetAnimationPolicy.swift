import Foundation

enum PetSelectableAction: String, CaseIterable {
    case sit = "坐坐"
    case photo = "拍照"
    case adventure = "探险"
    case beach = "海边"
    case dive = "潜水"
    case read = "看书"
    case paperPlane = "纸飞机"
    case shopping = "购物"
    case delivery = "送货"
    case riding = "骑行"
}

enum PetHorizontalEdge: String {
    case left
    case right
}

enum PetInteractionConfiguration {
    static let hoverDelay: TimeInterval = 0.6
    static let directInteractionRepeatCount = 3
    static let longPressDelay: TimeInterval = 0.8
    static let cursorFollowStationaryDelay: TimeInterval = 1
    static let cursorFollowSpeed: CGFloat = 150
    static let cursorFollowStoppingDistance: CGFloat = 56
    static let edgeDeliveryDelay: TimeInterval = 1
    static let bubbleAbsorptionDuration: TimeInterval = 0.30
    static let bubbleIconWidth: CGFloat = 40
    static let bubbleIconHeight = bubbleIconWidth
    static let bubbleIconHorizontalInset: CGFloat = 4
    static let bubbleOuterShadowPadding: CGFloat = 8
    static let bubbleVisualWidth = bubbleIconWidth + bubbleIconHorizontalInset * 2
    static let bubbleContactHeight = bubbleIconHeight * 5
    static let bubbleContactTangentLength = bubbleContactHeight * 0.22
    static let bubbleBodyHalfHeight = bubbleIconHeight / 2 + 4
    static let bubbleBodyJoinOffset = bubbleBodyHalfHeight
    static let bubbleJoinAngleDegrees: CGFloat = 25
    static let bubbleJoinAngleRadians = bubbleJoinAngleDegrees * .pi / 180
    static let bubbleArcSweepRadians = .pi / 2 - bubbleJoinAngleRadians
    static let bubbleArcControlFactor = (4.0 / 3.0) * tan(bubbleArcSweepRadians / 4)
    static let bubbleJoinTangentLength = bubbleArcControlFactor * bubbleBodyHalfHeight
    static let bubbleSize = CGSize(
        width: bubbleVisualWidth + bubbleOuterShadowPadding,
        height: bubbleContactHeight + 12
    )
}

enum PetDragDirectionPolicy {
    static func shouldMirror(horizontalDelta: CGFloat, currentMirrored: Bool) -> Bool {
        if horizontalDelta < -0.5 { return true }
        if horizontalDelta > 0.5 { return false }
        return currentMirrored
    }
}

enum PetBehaviorPolicy {
    static func bubbleSuctionProgress(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress))
        let firstPass = t * t * (3 - 2 * t)
        return firstPass * firstPass * (3 - 2 * firstPass)
    }

    static func horizontalEdge(for frame: CGRect, in visibleFrame: CGRect, tolerance: CGFloat = 0.5) -> PetHorizontalEdge? {
        if abs(frame.minX - visibleFrame.minX) <= tolerance { return .left }
        if abs(frame.maxX - visibleFrame.maxX) <= tolerance { return .right }
        return nil
    }

    static func edgeDeliveryShouldMirror(for edge: PetHorizontalEdge) -> Bool {
        edge == .right
    }

    static func bubbleFrame(
        edge: PetHorizontalEdge,
        fullPetFrame: CGRect,
        visibleFrame: CGRect,
        verticalInset: CGFloat = 2
    ) -> CGRect {
        let size = PetInteractionConfiguration.bubbleSize
        return CGRect(
            x: edge == .left ? visibleFrame.minX : visibleFrame.maxX - size.width,
            y: min(
                max(fullPetFrame.midY - size.height / 2, visibleFrame.minY + verticalInset),
                visibleFrame.maxY - size.height - verticalInset
            ),
            width: size.width,
            height: size.height
        )
    }

    static func cursorFollowOrigin(
        petFrame: CGRect,
        cursor: CGPoint,
        visibleFrame: CGRect,
        stoppingDistance: CGFloat = PetInteractionConfiguration.cursorFollowStoppingDistance
    ) -> CGPoint {
        let center = CGPoint(x: petFrame.midX, y: petFrame.midY)
        let dx = cursor.x - center.x
        let dy = cursor.y - center.y
        let distance = max(0.001, hypot(dx, dy))
        let travel = max(0, distance - stoppingDistance)
        let proposed = CGPoint(
            x: petFrame.origin.x + dx / distance * travel,
            y: petFrame.origin.y + dy / distance * travel
        )
        return DesktopPlacement.clampedOrigin(proposed, size: petFrame.size, visibleFrame: visibleFrame)
    }
}
