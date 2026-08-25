import Foundation

enum DesktopPlacement {
    static func clampedOrigin(_ origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }

    static func snappedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        threshold: CGFloat = 42
    ) -> CGPoint {
        var result = clampedOrigin(origin, size: size, visibleFrame: visibleFrame)
        if abs(result.x - visibleFrame.minX) <= threshold { result.x = visibleFrame.minX }
        if abs(result.x + size.width - visibleFrame.maxX) <= threshold {
            result.x = visibleFrame.maxX - size.width
        }
        if abs(result.y - visibleFrame.minY) <= threshold { result.y = visibleFrame.minY }
        if abs(result.y + size.height - visibleFrame.maxY) <= threshold {
            result.y = visibleFrame.maxY - size.height
        }
        return result
    }

    static func firstAvailableOrigin(
        candidates: [CGPoint],
        size: CGSize,
        visibleFrame: CGRect,
        occupiedFrames: [CGRect],
        clearance: CGFloat = 4
    ) -> CGPoint? {
        candidates.first { candidate in
            let frame = CGRect(origin: candidate, size: size)
            return visibleFrame.contains(frame) && !occupiedFrames.contains {
                $0.insetBy(dx: -clearance, dy: -clearance).intersects(frame)
            }
        }
    }

    static func leastOverlappingOrigin(
        candidates: [CGPoint],
        size: CGSize,
        visibleFrame: CGRect,
        occupiedFrames: [CGRect]
    ) -> CGPoint {
        let clamped = candidates.map { clampedOrigin($0, size: size, visibleFrame: visibleFrame) }
        return clamped.min { lhs, rhs in
            overlapArea(at: lhs, size: size, occupiedFrames: occupiedFrames) <
                overlapArea(at: rhs, size: size, occupiedFrames: occupiedFrames)
        } ?? clampedOrigin(.zero, size: size, visibleFrame: visibleFrame)
    }

    private static func overlapArea(at origin: CGPoint, size: CGSize, occupiedFrames: [CGRect]) -> CGFloat {
        let frame = CGRect(origin: origin, size: size)
        return occupiedFrames.reduce(0) {
            let intersection = $1.intersection(frame)
            return $0 + max(0, intersection.width) * max(0, intersection.height)
        }
    }
}
