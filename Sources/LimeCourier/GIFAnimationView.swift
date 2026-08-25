import AppKit
import ImageIO
import QuartzCore

private struct GIFFrame {
    let image: CGImage
    let duration: TimeInterval
    let alpha: [UInt8]
}

private final class GIFSequence: NSObject {
    let frames: [GIFFrame]
    let pixelCost: Int

    init(frames: [GIFFrame]) {
        self.frames = frames
        pixelCost = frames.reduce(0) { $0 + $1.image.width * $1.image.height * 5 }
    }
}

final class GIFAnimationView: NSView {
    private static let cache: NSCache<NSString, GIFSequence> = {
        let cache = NSCache<NSString, GIFSequence>()
        cache.totalCostLimit = 80 * 1_024 * 1_024
        return cache
    }()

    private var sequence: GIFSequence?
    private var frameIndex = 0
    private var completedLoops = 0
    private var repeatCount: Int?
    private var playbackRate = 1.0
    private var timer: Timer?
    private var completion: (() -> Void)?
    private let imageLayer = CALayer()

    private(set) var assetName: String?
    private(set) var isMirrored = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = bounds
        imageLayer.position = NSPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func play(
        assetName: String,
        maxPixelSize: Int,
        repeatCount: Int? = nil,
        playbackRate: Double = 1,
        completion: (() -> Void)? = nil
    ) {
        stop(clearImage: false)
        self.assetName = assetName
        self.repeatCount = repeatCount
        self.playbackRate = max(0.1, playbackRate)
        self.completion = completion

        let cacheKey = "\(assetName)-\(maxPixelSize)" as NSString
        if let cached = Self.cache.object(forKey: cacheKey) {
            start(cached)
            return
        }

        guard let url = ResourceLocator.url(for: assetName, extension: "gif", subdirectory: "GIF"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            finish()
            return
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(128, maxPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        let frames = (0..<CGImageSourceGetCount(source)).compactMap { index -> GIFFrame? in
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                return nil
            }
            return GIFFrame(
                image: image,
                duration: Self.frameDuration(source: source, index: index),
                alpha: Self.alphaMask(for: image)
            )
        }
        guard !frames.isEmpty else {
            finish()
            return
        }
        let loaded = GIFSequence(frames: frames)
        Self.cache.setObject(loaded, forKey: cacheKey, cost: loaded.pixelCost)
        start(loaded)
    }

    func stop(clearImage: Bool = true) {
        timer?.invalidate()
        timer = nil
        sequence = nil
        completion = nil
        frameIndex = 0
        completedLoops = 0
        if clearImage { imageLayer.contents = nil }
    }

    func setMirrored(_ mirrored: Bool) {
        guard mirrored != isMirrored else { return }
        isMirrored = mirrored
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
        CATransaction.commit()
    }

    func containsVisiblePixel(at point: CGPoint, alphaThreshold: UInt8 = 20) -> Bool {
        guard bounds.contains(point),
              let frame = sequence?.frames[safe: frameIndex] else { return false }
        let imageSize = CGSize(width: frame.image.width, height: frame.image.height)
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let renderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let renderedOrigin = CGPoint(
            x: bounds.midX - renderedSize.width / 2,
            y: bounds.midY - renderedSize.height / 2
        )
        guard CGRect(origin: renderedOrigin, size: renderedSize).contains(point) else { return false }

        var normalizedX = (point.x - renderedOrigin.x) / renderedSize.width
        if isMirrored { normalizedX = 1 - normalizedX }
        let normalizedY = (point.y - renderedOrigin.y) / renderedSize.height
        let x = min(frame.image.width - 1, max(0, Int(normalizedX * CGFloat(frame.image.width))))
        let y = min(frame.image.height - 1, max(0, Int(normalizedY * CGFloat(frame.image.height))))
        return frame.alpha[y * frame.image.width + x] >= alphaThreshold
    }

    private func start(_ sequence: GIFSequence) {
        self.sequence = sequence
        frameIndex = 0
        completedLoops = 0
        imageLayer.contents = sequence.frames[0].image
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        guard let frame = sequence?.frames[safe: frameIndex] else { return }
        timer?.invalidate()
        let nextTimer = Timer(timeInterval: frame.duration / playbackRate, repeats: false) { [weak self] _ in
            self?.advanceFrame()
        }
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    private func advanceFrame() {
        guard let sequence else { return }
        if frameIndex + 1 == sequence.frames.count {
            completedLoops += 1
            if let repeatCount, completedLoops >= repeatCount {
                timer = nil
                finish()
                return
            }
            frameIndex = 0
        } else {
            frameIndex += 1
        }
        imageLayer.contents = sequence.frames[frameIndex].image
        scheduleNextFrame()
    }

    private func finish() {
        let callback = completion
        completion = nil
        callback?()
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        return max(0.04, unclamped ?? clamped ?? 0.1)
    }

    private static func alphaMask(for image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}

final class EdgeBubbleView: NSView {
    private struct Geometry {
        let path: NSBezierPath
        let iconRect: CGRect
        let contactX: CGFloat
        let circleCenter: CGPoint
        let circleRadius: CGFloat
    }

    var edge: PetHorizontalEdge = .right {
        didSet { needsDisplay = true }
    }
    var transitionProgress: CGFloat = 1 {
        didSet {
            transitionProgress = min(1, max(0, transitionProgress))
            needsDisplay = true
        }
    }
    var isHovered = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }

    private lazy var icon: NSImage? = {
        guard let url = ResourceLocator.url(for: "7", extension: "png", subdirectory: "UI素材") else { return nil }
        return NSImage(contentsOf: url)
    }()

    // The source PNG has transparent padding. This is the 25%-alpha content bounds.
    private let iconSourceRect = CGRect(x: 8, y: 5, width: 69, height: 65)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let geometry = bubbleGeometry()
        let body = geometry.path
        let presentationAlpha = 0.72 + transitionProgress * 0.28

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(presentationAlpha)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: 3)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.withAlphaComponent(0.78).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()

        let fill = NSGradient(colors: [
            NSColor.white.withAlphaComponent(isHovered ? 0.42 : 0.34),
            NSColor(calibratedRed: 0.80, green: 0.90, blue: 0.90, alpha: 0.18)
        ])
        fill?.draw(in: body, angle: 90)

        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        let volumeShade = NSGradient(colors: [
            NSColor.clear,
            NSColor(calibratedRed: 0.36, green: 0.49, blue: 0.50, alpha: 0.16)
        ])
        volumeShade?.draw(in: bounds, angle: 90)

        let highlight = NSGradient(colors: [
            NSColor.white.withAlphaComponent(isHovered ? 0.62 : 0.50),
            NSColor.white.withAlphaComponent(0)
        ])
        let highlightCenter = CGPoint(
            x: geometry.circleCenter.x - 7,
            y: geometry.circleCenter.y - 8
        )
        highlight?.draw(
            fromCenter: highlightCenter,
            radius: 0,
            toCenter: highlightCenter,
            radius: geometry.circleRadius * 1.12,
            options: [.drawsAfterEndingLocation]
        )

        let contactShade = NSGradient(colors: [
            NSColor(calibratedRed: 0.22, green: 0.34, blue: 0.35, alpha: 0.15),
            NSColor.clear
        ])
        let direction: CGFloat = edge == .left ? 1 : -1
        contactShade?.draw(
            from: CGPoint(x: geometry.contactX, y: bounds.midY),
            to: CGPoint(x: geometry.contactX + direction * 12, y: bounds.midY),
            options: [.drawsAfterEndingLocation]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(isHovered ? 0.56 : 0.44).setStroke()
        body.lineWidth = 1
        body.stroke()

        guard let icon else {
            context.restoreGState()
            return
        }
        let iconRect = geometry.iconRect
        let iconShadow = NSShadow()
        iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.09)
        iconShadow.shadowBlurRadius = 2
        iconShadow.shadowOffset = NSSize(width: 0, height: 1)
        NSGraphicsContext.saveGraphicsState()
        iconShadow.set()
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: iconRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: iconRect).addClip()
        icon.draw(
            in: iconRect,
            from: iconSourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    func containsVisiblePoint(_ point: CGPoint) -> Bool {
        bubbleGeometry().path.contains(point)
    }

    private func bubbleGeometry() -> Geometry {
        let path = NSBezierPath()
        let contactX: CGFloat = edge == .left ? 0 : bounds.maxX
        let direction: CGFloat = edge == .left ? 1 : -1
        let centerY = bounds.midY
        let finalRadius = PetInteractionConfiguration.bubbleBodyHalfHeight
        let circleRadius = finalRadius * (1.15 - transitionProgress * 0.15)
        let finalCenterDistance = finalRadius
        let initialCenterDistance = max(finalCenterDistance, min(72, bounds.width / 2))
        let centerDistance = initialCenterDistance
            + (finalCenterDistance - initialCenterDistance) * transitionProgress
        let circleCenter = CGPoint(
            x: contactX + direction * centerDistance,
            y: centerY
        )
        let outerX = circleCenter.x + direction * circleRadius
        let iconSize = max(1, (circleRadius - PetInteractionConfiguration.bubbleIconHorizontalInset) * 2)
        let iconRect = CGRect(
            x: circleCenter.x - iconSize / 2,
            y: centerY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        let initialContactHeight = iconSize * 1.6
        let contactHeight = initialContactHeight
            + (PetInteractionConfiguration.bubbleContactHeight - initialContactHeight) * transitionProgress
        let contactHalfHeight = contactHeight / 2
        let contactTop = centerY - contactHalfHeight
        let contactBottom = centerY + contactHalfHeight
        let contactTangent = contactHeight * 0.22
        let radiusX = circleRadius
        let radiusY = circleRadius
        let angle = PetInteractionConfiguration.bubbleJoinAngleRadians
        let sinAngle = sin(angle)
        let cosAngle = cos(angle)
        let upperJoin = CGPoint(
            x: circleCenter.x + direction * radiusX * sinAngle,
            y: centerY - radiusY * cosAngle
        )
        let lowerJoin = CGPoint(
            x: upperJoin.x,
            y: centerY + radiusY * cosAngle
        )
        let upperDerivative = CGVector(
            dx: direction * radiusX * cosAngle,
            dy: radiusY * sinAngle
        )
        let derivativeLength = hypot(upperDerivative.dx, upperDerivative.dy)
        let arcControlFactor = PetInteractionConfiguration.bubbleArcControlFactor
        let joinTangent = arcControlFactor * circleRadius
        let upperUnitTangent = CGVector(
            dx: upperDerivative.dx / derivativeLength,
            dy: upperDerivative.dy / derivativeLength
        )
        let lowerUnitTangent = CGVector(
            dx: -upperUnitTangent.dx,
            dy: upperUnitTangent.dy
        )
        let upperArcControl1 = CGPoint(
            x: upperJoin.x + arcControlFactor * upperDerivative.dx,
            y: upperJoin.y + arcControlFactor * upperDerivative.dy
        )
        let upperArcControl2 = CGPoint(
            x: outerX,
            y: centerY - arcControlFactor * radiusY
        )
        let lowerArcControl1 = CGPoint(
            x: outerX,
            y: centerY + arcControlFactor * radiusY
        )
        let lowerDerivative = CGVector(
            dx: -direction * radiusX * cosAngle,
            dy: radiusY * sinAngle
        )
        let lowerArcControl2 = CGPoint(
            x: lowerJoin.x - arcControlFactor * lowerDerivative.dx,
            y: lowerJoin.y - arcControlFactor * lowerDerivative.dy
        )

        path.move(to: CGPoint(x: contactX, y: contactBottom))
        path.line(to: CGPoint(x: contactX, y: contactTop))
        path.curve(
            to: upperJoin,
            controlPoint1: CGPoint(x: contactX, y: contactTop + contactTangent),
            controlPoint2: CGPoint(
                x: upperJoin.x - upperUnitTangent.dx * joinTangent,
                y: upperJoin.y - upperUnitTangent.dy * joinTangent
            )
        )
        path.curve(
            to: CGPoint(x: outerX, y: centerY),
            controlPoint1: upperArcControl1,
            controlPoint2: upperArcControl2
        )
        path.curve(
            to: lowerJoin,
            controlPoint1: lowerArcControl1,
            controlPoint2: lowerArcControl2
        )
        path.curve(
            to: CGPoint(x: contactX, y: contactBottom),
            controlPoint1: CGPoint(
                x: lowerJoin.x + lowerUnitTangent.dx * joinTangent,
                y: lowerJoin.y + lowerUnitTangent.dy * joinTangent
            ),
            controlPoint2: CGPoint(x: contactX, y: contactBottom - contactTangent)
        )
        path.close()
        return Geometry(
            path: path,
            iconRect: iconRect,
            contactX: contactX,
            circleCenter: circleCenter,
            circleRadius: circleRadius
        )
    }
}

@MainActor
protocol PetInteractionViewDelegate: AnyObject {
    func petViewSingleClicked()
    func petViewDoubleClicked()
    func petViewLongPressed()
    func petViewDragged(to origin: NSPoint)
    func petViewDragEnded(at origin: NSPoint)
    func petViewRightClicked(event: NSEvent, in view: NSView)
    func petViewHoverChanged(isInside: Bool)
}

final class PetInteractionView: NSView {
    let animationView = GIFAnimationView(frame: .zero)
    private let bubbleView = EdgeBubbleView(frame: .zero)
    weak var delegate: PetInteractionViewDelegate?

    private var mouseDownScreenPoint = NSPoint.zero
    private var initialWindowOrigin = NSPoint.zero
    private var didDrag = false
    private var trackingAreaRef: NSTrackingArea?
    private var singleClickWorkItem: DispatchWorkItem?
    private var longPressWorkItem: DispatchWorkItem?
    private var didLongPress = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        animationView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.isHidden = true
        addSubview(animationView)
        addSubview(bubbleView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        mouseDownScreenPoint = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
        didDrag = false
        didLongPress = false
        longPressWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.didDrag else { return }
            self.didLongPress = true
            self.singleClickWorkItem?.cancel()
            self.delegate?.petViewLongPressed()
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PetInteractionConfiguration.longPressDelay,
            execute: work
        )
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - mouseDownScreenPoint.x, y: current.y - mouseDownScreenPoint.y)
        if abs(delta.x) > 4 || abs(delta.y) > 4 {
            didDrag = true
            longPressWorkItem?.cancel()
        }
        delegate?.petViewDragged(to: NSPoint(x: initialWindowOrigin.x + delta.x, y: initialWindowOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        if didDrag {
            singleClickWorkItem?.cancel()
            delegate?.petViewDragEnded(at: window?.frame.origin ?? .zero)
            return
        }

        if didLongPress {
            didLongPress = false
            return
        }

        if event.clickCount >= 2 {
            singleClickWorkItem?.cancel()
            singleClickWorkItem = nil
            delegate?.petViewDoubleClicked()
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.delegate?.petViewSingleClicked()
            }
            singleClickWorkItem?.cancel()
            singleClickWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.petViewRightClicked(event: event, in: self)
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.petViewHoverChanged(isInside: true)
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.petViewHoverChanged(isInside: false)
    }

    func containsVisiblePixel(at point: CGPoint) -> Bool {
        if !bubbleView.isHidden {
            return bubbleView.containsVisiblePoint(convert(point, to: bubbleView))
        }
        return animationView.containsVisiblePixel(at: convert(point, to: animationView))
    }

    func setBubbleMode(edge: PetHorizontalEdge?) {
        if let edge {
            bubbleView.edge = edge
            bubbleView.isHovered = false
            bubbleView.isHidden = false
            animationView.isHidden = true
        } else {
            bubbleView.transitionProgress = 1
            bubbleView.isHovered = false
            bubbleView.isHidden = true
            animationView.isHidden = false
        }
    }

    func setBubbleTransitionProgress(_ progress: CGFloat) {
        bubbleView.transitionProgress = progress
    }

    func setBubbleHovered(_ hovered: Bool) {
        bubbleView.isHovered = hovered
    }

    func showAffectionEffect() {
        guard let url = ResourceLocator.url(for: "22", extension: "png", subdirectory: "UI素材"),
              let image = NSImage(contentsOf: url),
              let contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let offsets: [CGPoint] = [CGPoint(x: -26, y: 2), CGPoint(x: 0, y: 15), CGPoint(x: 25, y: -1)]
        for (index, offset) in offsets.enumerated() {
            let star = CALayer()
            star.contents = contents
            star.contentsGravity = .resizeAspect
            star.frame = CGRect(x: bounds.midX + offset.x - 12, y: bounds.height * 0.72 + offset.y, width: 24, height: 24)
            layer?.addSublayer(star)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, 0.2, 0.65, 1]
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.45
            scale.toValue = 1.25
            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            group.duration = 0.8
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.08
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { star.removeFromSuperlayer() }
            star.add(group, forKey: "affection")
            CATransaction.commit()
        }
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
