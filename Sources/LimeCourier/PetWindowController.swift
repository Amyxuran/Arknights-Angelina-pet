import AppKit
import Combine

final class NonActivatingPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetWindowController: NSObject, PetInteractionViewDelegate {
    private enum Mode: String {
        case idle = "休息中"
        case direct = "回应中"
        case dragging = "跟随拖动"
        case moving = "散步中"
        case bubble = "边缘气泡"
    }

    private enum MovementKind {
        case autonomous
        case follow
    }

    private struct Movement {
        let from: CGPoint
        let to: CGPoint
        let startedAt: Date
        let duration: TimeInterval
        let kind: MovementKind
        let completion: (() -> Void)?
    }

    private struct BubbleTransition {
        let targetFrame: CGRect
        let startedAt: Date
        let duration: TimeInterval
    }

    private let preferences: AppPreferences
    private let panel: NonActivatingPetPanel
    private let petView: PetInteractionView
    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    private var behaviorTimer: Timer?
    private var movement: Movement?
    private var bubbleTransition: BubbleTransition?
    private var mode: Mode = .idle { didSet { onStateChanged?() } }
    private var currentAsset = "坐坐" { didSet { onStateChanged?() } }
    private var oneShotToken = UUID()
    private var hoverWorkItem: DispatchWorkItem?
    private var hoverInside = false
    private var hoverLoopActive = false
    private var lastActivityAt = Date()
    private var nextRoamAt = Date()
    private var cursorStationarySince: Date?
    private var lastCursorLocation: CGPoint?
    private var lastDragOrigin = CGPoint.zero
    private var snappedEdge: PetHorizontalEdge?
    private var fullEdgeOrigin: CGPoint?
    private var edgeDeliveryDeadline: Date?
    private var bubbleHoverStartedAt: Date?
    private var dragOriginAdjustment = CGPoint.zero
    private var suppressDirectClickUntil = Date.distantPast

    var contextMenuProvider: (() -> NSMenu)?
    var onStateChanged: (() -> Void)?

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var statusTitle: String { "\(mode.rawValue) · \(currentAsset)" }
    var animationAssetForQA: String { currentAsset }
    var animationMirroredForQA: Bool { petView.animationView.isMirrored }
    var isBubbleForQA: Bool { mode == .bubble }
    var persistedOrigin: CGPoint { fullEdgeOrigin ?? panel.frame.origin }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        let size = preferences.petSize
        panel = NonActivatingPetPanel(
            contentRect: CGRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        petView = PetInteractionView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        super.init()

        petView.delegate = self
        panel.contentView = petView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        updateWindowLevel()
        restoreOrPlaceWindow()
        observePreferences()
        scheduleAutonomousEvents(from: .now)
    }

    func show() {
        guard !panel.isVisible else { return }
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = false
        startIdleLoop()
        startTimers()
        onStateChanged?()
    }

    func hide() {
        hoverWorkItem?.cancel()
        hoverLoopActive = false
        movement = nil
        bubbleTransition = nil
        heartbeatTimer?.invalidate()
        behaviorTimer?.invalidate()
        heartbeatTimer = nil
        behaviorTimer = nil
        petView.animationView.stop()
        panel.orderOut(nil)
        onStateChanged?()
    }

    func resetPosition() {
        preferences.resetPetOrigin()
        revealImmediatelyIfNeeded()
        placeAtDefaultPosition()
        clearEdgeState()
        preferences.savePetOrigin(panel.frame.origin)
        markActivity()
    }

    func writeVisualSnapshot(to url: URL) throws {
        guard let data = petView.renderedPNGData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    func playAssetForQA(_ assetName: String, mirrored: Bool = false) {
        cancelMovement()
        mode = .direct
        currentAsset = assetName
        petView.animationView.setMirrored(mirrored)
        petView.animationView.play(
            assetName: assetName,
            maxPixelSize: renderPixelSize,
            repeatCount: nil,
            playbackRate: preferences.animationSpeed
        )
    }

    func showLongPressEffectForQA() {
        petView.showAffectionEffect()
    }

    func showBubbleForQA(edge: PetHorizontalEdge) {
        cancelMovement()
        mode = .idle
        let visible = activeScreen().visibleFrame
        let full = edge == .left
            ? CGPoint(x: visible.minX, y: panel.frame.origin.y)
            : CGPoint(x: visible.maxX - panel.frame.width, y: panel.frame.origin.y)
        panel.setFrameOrigin(full)
        snappedEdge = edge
        fullEdgeOrigin = full
        enterBubble(edge: edge, animated: false)
    }

    func showBubbleTransitionForQA(edge: PetHorizontalEdge, rawProgress: CGFloat) {
        cancelMovement()
        bubbleTransition = nil
        let visible = activeScreen().visibleFrame
        let size = CGSize(width: preferences.petSize, height: preferences.petSize)
        let y = min(
            max(panel.frame.midY - size.height / 2, visible.minY),
            visible.maxY - size.height
        )
        let origin = CGPoint(
            x: edge == .left ? visible.minX : visible.maxX - size.width,
            y: y
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        snappedEdge = edge
        fullEdgeOrigin = origin
        mode = .bubble
        currentAsset = "7"
        petView.animationView.stop()
        petView.setBubbleMode(edge: edge)
        petView.setBubbleTransitionProgress(PetBehaviorPolicy.bubbleSuctionProgress(rawProgress))
    }

    func restoreAfterQA(origin: CGPoint) {
        cancelMovement()
        petView.setBubbleMode(edge: nil)
        panel.setFrame(
            CGRect(
                origin: origin,
                size: CGSize(width: preferences.petSize, height: preferences.petSize)
            ),
            display: true
        )
        clearEdgeState()
        startIdleLoop()
    }

    func petViewSingleClicked() {
        guard Date() >= suppressDirectClickUntil else { return }
        if mode == .bubble { revealFromEdge(animated: true); return }
        performDirectInteraction(
            assetName: "纸飞机",
            repeatCount: PetInteractionConfiguration.directInteractionRepeatCount
        )
    }

    func petViewDoubleClicked() {
        guard Date() >= suppressDirectClickUntil else { return }
        if mode == .bubble { revealFromEdge(animated: true); return }
        performDirectInteraction(
            assetName: "购物",
            repeatCount: PetInteractionConfiguration.directInteractionRepeatCount
        )
    }

    func petViewLongPressed() {
        guard Date() >= suppressDirectClickUntil else { return }
        if mode == .bubble { revealFromEdge(animated: true); return }
        petView.showAffectionEffect()
        performDirectInteraction(assetName: "海边", repeatCount: 1)
    }

    func petViewDragged(to origin: NSPoint) {
        var adjustedOrigin = origin
        if mode == .bubble, let fullOrigin = fullEdgeOrigin {
            dragOriginAdjustment = CGPoint(
                x: fullOrigin.x - panel.frame.origin.x,
                y: fullOrigin.y - panel.frame.origin.y
            )
            revealImmediatelyIfNeeded()
        }
        adjustedOrigin.x += dragOriginAdjustment.x
        adjustedOrigin.y += dragOriginAdjustment.y
        if mode != .dragging {
            hoverWorkItem?.cancel()
            cancelMovement()
            mode = .dragging
            currentAsset = "骑行"
            lastDragOrigin = panel.frame.origin
            clearEdgeState()
            petView.animationView.play(
                assetName: "骑行",
                maxPixelSize: renderPixelSize,
                repeatCount: nil,
                playbackRate: preferences.animationSpeed
            )
        }
        let deltaX = adjustedOrigin.x - lastDragOrigin.x
        petView.animationView.setMirrored(
            PetDragDirectionPolicy.shouldMirror(
                horizontalDelta: deltaX,
                currentMirrored: petView.animationView.isMirrored
            )
        )
        panel.setFrameOrigin(adjustedOrigin)
        lastDragOrigin = adjustedOrigin
        markActivity()
    }

    func petViewDragEnded(at origin: NSPoint) {
        guard mode == .dragging else { return }
        dragOriginAdjustment = .zero
        let screen = screen(containing: CGRect(origin: origin, size: panel.frame.size))
        let target = DesktopPlacement.snappedOrigin(
            origin,
            size: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            threshold: 42
        )
        panel.setFrameOrigin(target)
        preferences.savePetOrigin(target)
        let edge = PetBehaviorPolicy.horizontalEdge(for: panel.frame, in: screen.visibleFrame)
        snappedEdge = edge
        fullEdgeOrigin = edge == nil ? nil : target
        edgeDeliveryDeadline = edge == nil
            ? nil
            : Date().addingTimeInterval(PetInteractionConfiguration.edgeDeliveryDelay)
        startIdleLoop()
    }

    func petViewRightClicked(event: NSEvent, in view: NSView) {
        guard let menu = contextMenuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func petViewHoverChanged(isInside: Bool) {
        hoverInside = isInside
        hoverWorkItem?.cancel()
        if !isInside, hoverLoopActive {
            hoverLoopActive = false
            startIdleLoop()
        }
        guard isInside,
              mode == .idle,
              edgeDeliveryDeadline == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.hoverInside,
                  self.mode == .idle,
                  self.edgeDeliveryDeadline == nil else { return }
            self.startHoverLoop()
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PetInteractionConfiguration.hoverDelay,
            execute: work
        )
    }

    private var renderPixelSize: Int {
        Int(max(256, preferences.petSize * 2))
    }

    private func observePreferences() {
        preferences.$petSize
            .removeDuplicates()
            .sink { [weak self] size in self?.resize(to: size) }
            .store(in: &cancellables)

        preferences.$alwaysOnTop
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateWindowLevel() }
            .store(in: &cancellables)

        preferences.$edgeHideEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    if self.snappedEdge != nil, self.mode == .idle {
                        self.edgeDeliveryDeadline = Date().addingTimeInterval(PetInteractionConfiguration.edgeDeliveryDelay)
                    }
                } else {
                    self.revealFromEdge(animated: true)
                }
            }
            .store(in: &cancellables)

        preferences.$autonomousEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.scheduleAutonomousEvents(from: .now)
                } else if self.movement?.kind == .autonomous {
                    self.cancelMovement()
                    self.startIdleLoop()
                }
            }
            .store(in: &cancellables)

        preferences.$mouseFollowEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.cursorStationarySince = nil
                    self.lastCursorLocation = nil
                    if self.movement?.kind == .follow {
                        self.cancelMovement()
                        self.startIdleLoop()
                    }
                }
            }
            .store(in: &cancellables)

        preferences.$animationSpeed
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.mode == .idle else { return }
                self.startIdleLoop()
            }
            .store(in: &cancellables)

        preferences.$selectedStandbyAction
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] action in
                guard let self, self.mode == .idle else { return }
                self.startIdleLoop(action: action)
            }
            .store(in: &cancellables)
    }

    private func updateWindowLevel() {
        panel.level = preferences.alwaysOnTop ? .floating : .normal
    }

    private func restoreOrPlaceWindow() {
        guard let saved = preferences.savedPetOrigin else {
            placeAtDefaultPosition()
            return
        }
        let screen = screen(containing: CGRect(origin: saved, size: panel.frame.size))
        panel.setFrameOrigin(DesktopPlacement.clampedOrigin(saved, size: panel.frame.size, visibleFrame: screen.visibleFrame))
    }

    private func placeAtDefaultPosition() {
        let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        panel.setFrameOrigin(CGPoint(
            x: visible.maxX - panel.frame.width - 48,
            y: visible.minY + 64
        ))
    }

    private func resize(to requestedSize: Double) {
        let size = AppPreferences.normalizedSize(requestedSize)
        guard abs(panel.frame.width - size) > 0.5 else { return }
        revealImmediatelyIfNeeded()
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let newSize = CGSize(width: size, height: size)
        let proposed = CGPoint(x: center.x - size / 2, y: center.y - size / 2)
        let visible = activeScreen().visibleFrame
        let origin = DesktopPlacement.clampedOrigin(proposed, size: newSize, visibleFrame: visible)
        panel.setFrame(CGRect(origin: origin, size: newSize), display: true)
        preferences.savePetOrigin(origin)
        clearEdgeState()
        if panel.isVisible { startIdleLoop() }
    }

    private func startTimers() {
        heartbeatTimer?.invalidate()
        behaviorTimer?.invalidate()
        let heartbeat = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        heartbeatTimer = heartbeat
        RunLoop.main.add(heartbeat, forMode: .common)
        let behavior = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateBehavior() }
        }
        behaviorTimer = behavior
        RunLoop.main.add(behavior, forMode: .common)
    }

    private func heartbeat() {
        updateMovement()
        updateBubbleTransition()
        updateMousePassThrough()
        updateBubbleHover()
        evaluateEdgeDelivery()
        evaluateCursorFollow()
    }

    private func evaluateEdgeDelivery() {
        guard mode == .idle,
              let edge = snappedEdge,
              let deadline = edgeDeliveryDeadline,
              Date() >= deadline else { return }
        beginEdgeDelivery(edge: edge)
    }

    private func updateMousePassThrough() {
        guard panel.isVisible else { return }
        let cursor = NSEvent.mouseLocation
        guard panel.frame.contains(cursor) else {
            panel.ignoresMouseEvents = true
            if hoverInside, mode != .bubble {
                petViewHoverChanged(isInside: false)
            }
            return
        }
        let local = CGPoint(x: cursor.x - panel.frame.minX, y: cursor.y - panel.frame.minY)
        let overVisibleContent = petView.containsVisiblePixel(at: local)
        panel.ignoresMouseEvents = !overVisibleContent
        if overVisibleContent, !hoverInside, mode != .bubble {
            petViewHoverChanged(isInside: true)
        }
    }

    private func evaluateBehavior() {
        guard panel.isVisible else { return }
        let now = Date()
        guard preferences.autonomousEnabled,
              mode == .idle,
              now.timeIntervalSince(lastActivityAt) >= 8 else { return }
        if now >= nextRoamAt {
            beginAutonomousMovement()
            nextRoamAt = now.addingTimeInterval(.random(in: 60...150))
        }
    }

    private func evaluateCursorFollow() {
        guard preferences.mouseFollowEnabled, panel.isVisible else {
            cursorStationarySince = nil
            lastCursorLocation = nil
            return
        }
        let cursor = NSEvent.mouseLocation
        if let previous = lastCursorLocation,
           hypot(cursor.x - previous.x, cursor.y - previous.y) > 3 {
            lastCursorLocation = cursor
            cursorStationarySince = .now
            if movement?.kind == .follow {
                cancelMovement()
                startIdleLoop()
            }
            return
        }
        if lastCursorLocation == nil {
            lastCursorLocation = cursor
            cursorStationarySince = .now
            return
        }
        guard Date().timeIntervalSince(cursorStationarySince ?? .now) >= PetInteractionConfiguration.cursorFollowStationaryDelay else {
            return
        }
        if movement?.kind == .autonomous {
            cancelMovement()
            startIdleLoop()
        }
        if mode == .bubble { revealImmediatelyIfNeeded() }
        guard mode == .idle else { return }
        let distance = hypot(cursor.x - panel.frame.midX, cursor.y - panel.frame.midY)
        guard distance > PetInteractionConfiguration.cursorFollowStoppingDistance else { return }
        clearEdgeState()
        let cursorScreen = screen(containing: CGRect(x: cursor.x, y: cursor.y, width: 1, height: 1))
        let target = PetBehaviorPolicy.cursorFollowOrigin(
            petFrame: panel.frame,
            cursor: cursor,
            visibleFrame: cursorScreen.visibleFrame
        )
        startMovement(
            to: target,
            speed: PetInteractionConfiguration.cursorFollowSpeed,
            kind: .follow,
            assetName: "骑行"
        ) { [weak self] in
            self?.preferences.savePetOrigin(target)
            self?.startIdleLoop()
        }
    }

    private func beginAutonomousMovement() {
        clearEdgeState()
        let visible = activeScreen().visibleFrame
        let horizontal = CGFloat.random(in: 100...280) * (Bool.random() ? 1 : -1)
        let vertical = CGFloat.random(in: -80...80)
        let proposed = CGPoint(x: panel.frame.minX + horizontal, y: panel.frame.minY + vertical)
        let target = DesktopPlacement.clampedOrigin(proposed, size: panel.frame.size, visibleFrame: visible)
        guard hypot(target.x - panel.frame.minX, target.y - panel.frame.minY) >= 20 else { return }
        startMovement(to: target, speed: 80, kind: .autonomous, assetName: "骑行") { [weak self] in
            self?.preferences.savePetOrigin(target)
            self?.startIdleLoop()
        }
    }

    private func startMovement(
        to target: CGPoint,
        speed: CGFloat,
        kind: MovementKind,
        assetName: String,
        completion: (() -> Void)?
    ) {
        cancelMovement()
        let origin = panel.frame.origin
        let distance = hypot(target.x - origin.x, target.y - origin.y)
        let duration = max(0.18, TimeInterval(distance / max(1, speed)))
        movement = Movement(from: origin, to: target, startedAt: .now, duration: duration, kind: kind, completion: completion)
        mode = .moving
        currentAsset = assetName
        petView.animationView.setMirrored(target.x < origin.x)
        petView.animationView.play(
            assetName: assetName,
            maxPixelSize: renderPixelSize,
            repeatCount: nil,
            playbackRate: preferences.animationSpeed
        )
    }

    private func updateMovement() {
        guard let movement else { return }
        let progress = min(1, Date().timeIntervalSince(movement.startedAt) / movement.duration)
        let interpolation = movement.kind == .follow
            ? progress
            : progress * progress * (3 - 2 * progress)
        panel.setFrameOrigin(CGPoint(
            x: movement.from.x + (movement.to.x - movement.from.x) * interpolation,
            y: movement.from.y + (movement.to.y - movement.from.y) * interpolation
        ))
        if progress >= 1 {
            self.movement = nil
            movement.completion?()
        }
    }

    private func updateBubbleTransition() {
        guard mode == .bubble, let transition = bubbleTransition else { return }
        let elapsed = Date().timeIntervalSince(transition.startedAt)
        let rawProgress = min(1, max(0, elapsed / transition.duration))
        let easedProgress = PetBehaviorPolicy.bubbleSuctionProgress(CGFloat(rawProgress))
        petView.setBubbleTransitionProgress(easedProgress)
        if rawProgress >= 1 {
            bubbleTransition = nil
            panel.setFrame(transition.targetFrame, display: true)
            petView.setBubbleTransitionProgress(1)
        }
    }

    private func cancelMovement() {
        movement = nil
    }

    private func performDirectInteraction(
        assetName: String,
        repeatCount: Int,
        preserveEdge: Bool = true
    ) {
        hoverWorkItem?.cancel()
        hoverLoopActive = false
        cancelMovement()
        if !preserveEdge { clearEdgeState() }
        markActivity()
        playOneShot(assetName: assetName, repeatCount: repeatCount, mode: .direct)
    }

    private func playOneShot(
        assetName: String,
        repeatCount: Int,
        mode targetMode: Mode,
        mirrored: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let token = UUID()
        oneShotToken = token
        mode = targetMode
        currentAsset = assetName
        petView.setBubbleMode(edge: nil)
        petView.animationView.setMirrored(mirrored)
        petView.animationView.play(
            assetName: assetName,
            maxPixelSize: renderPixelSize,
            repeatCount: repeatCount,
            playbackRate: preferences.animationSpeed
        ) { [weak self] in
            guard let self, self.oneShotToken == token, self.mode == targetMode else { return }
            if let completion {
                completion()
            } else {
                self.returnAfterAction()
            }
        }
    }

    private func startHoverLoop() {
        guard hoverInside,
              edgeDeliveryDeadline == nil,
              mode != .bubble else { return }
        oneShotToken = UUID()
        hoverLoopActive = true
        mode = .direct
        currentAsset = "拍照"
        petView.setBubbleMode(edge: nil)
        petView.animationView.setMirrored(false)
        petView.animationView.play(
            assetName: "拍照",
            maxPixelSize: renderPixelSize,
            repeatCount: nil,
            playbackRate: preferences.animationSpeed
        )
    }

    private func returnAfterAction() {
        if hoverInside, edgeDeliveryDeadline == nil {
            startHoverLoop()
        } else {
            startIdleLoop()
        }
    }

    private func startIdleLoop(action requestedAction: PetSelectableAction? = nil) {
        movement = nil
        hoverLoopActive = false
        mode = .idle
        let action = requestedAction ?? preferences.selectedStandbyAction
        currentAsset = action.rawValue
        petView.setBubbleMode(edge: nil)
        petView.animationView.setMirrored(false)
        oneShotToken = UUID()
        petView.animationView.play(
            assetName: action.rawValue,
            maxPixelSize: renderPixelSize,
            repeatCount: nil,
            playbackRate: preferences.animationSpeed
        )
    }

    private func markActivity() {
        let now = Date()
        lastActivityAt = now
        scheduleAutonomousEvents(from: now)
    }

    private func scheduleAutonomousEvents(from date: Date) {
        nextRoamAt = date.addingTimeInterval(.random(in: 60...150))
    }

    private func beginEdgeDelivery(edge: PetHorizontalEdge) {
        edgeDeliveryDeadline = nil
        hoverWorkItem?.cancel()
        hoverLoopActive = false
        playOneShot(
            assetName: "送货",
            repeatCount: 1,
            mode: .direct,
            mirrored: PetBehaviorPolicy.edgeDeliveryShouldMirror(for: edge)
        ) { [weak self] in
            guard let self else { return }
            if self.preferences.edgeHideEnabled {
                self.enterBubble(edge: edge, animated: true)
            } else {
                self.clearEdgeState()
                self.returnAfterAction()
            }
        }
    }

    private func enterBubble(edge: PetHorizontalEdge, animated: Bool) {
        guard let fullOrigin = fullEdgeOrigin else { return }
        let fullSize = CGSize(width: preferences.petSize, height: preferences.petSize)
        let fullFrame = CGRect(origin: fullOrigin, size: fullSize)
        let visible = screen(containing: fullFrame).visibleFrame
        oneShotToken = UUID()
        mode = .bubble
        currentAsset = "7"
        petView.animationView.stop()
        petView.setBubbleMode(edge: edge)
        let targetFrame = PetBehaviorPolicy.bubbleFrame(
            edge: edge,
            fullPetFrame: fullFrame,
            visibleFrame: visible
        )
        if animated {
            panel.setFrame(fullFrame, display: true)
            petView.setBubbleTransitionProgress(0)
            bubbleTransition = BubbleTransition(
                targetFrame: targetFrame,
                startedAt: .now,
                duration: PetInteractionConfiguration.bubbleAbsorptionDuration
            )
        } else {
            bubbleTransition = nil
            panel.setFrame(targetFrame, display: true)
            petView.setBubbleTransitionProgress(1)
        }
    }

    private func updateBubbleHover() {
        guard mode == .bubble else {
            bubbleHoverStartedAt = nil
            return
        }
        guard bubbleTransition == nil else {
            bubbleHoverStartedAt = nil
            petView.setBubbleHovered(false)
            return
        }
        let cursor = NSEvent.mouseLocation
        guard panel.frame.contains(cursor) else {
            bubbleHoverStartedAt = nil
            petView.setBubbleHovered(false)
            return
        }
        let local = CGPoint(x: cursor.x - panel.frame.minX, y: cursor.y - panel.frame.minY)
        guard petView.containsVisiblePixel(at: local) else {
            bubbleHoverStartedAt = nil
            petView.setBubbleHovered(false)
            return
        }
        petView.setBubbleHovered(true)
        if bubbleHoverStartedAt == nil {
            bubbleHoverStartedAt = .now
        } else if Date().timeIntervalSince(bubbleHoverStartedAt ?? .now) >= 0.4 {
            bubbleHoverStartedAt = nil
            revealFromEdge(animated: true)
        }
    }

    private func revealFromEdge(animated: Bool) {
        guard mode == .bubble,
              let edge = snappedEdge,
              let storedOrigin = fullEdgeOrigin else { return }
        cancelMovement()
        bubbleTransition = nil
        let visible = activeScreen().visibleFrame
        let size = CGSize(width: preferences.petSize, height: preferences.petSize)
        var target = DesktopPlacement.clampedOrigin(storedOrigin, size: size, visibleFrame: visible)
        target.x = edge == .left ? visible.minX : visible.maxX - size.width
        let targetFrame = CGRect(origin: target, size: size)
        suppressDirectClickUntil = Date().addingTimeInterval(0.8)
        clearEdgeState()
        petView.setBubbleMode(edge: nil)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
        preferences.savePetOrigin(target)
        playOneShot(assetName: "探险", repeatCount: 1, mode: .direct, mirrored: edge == .right)
    }

    private func revealImmediatelyIfNeeded() {
        guard mode == .bubble,
              let edge = snappedEdge,
              let storedOrigin = fullEdgeOrigin else { return }
        cancelMovement()
        bubbleTransition = nil
        let visible = activeScreen().visibleFrame
        let size = CGSize(width: preferences.petSize, height: preferences.petSize)
        var origin = DesktopPlacement.clampedOrigin(storedOrigin, size: size, visibleFrame: visible)
        origin.x = edge == .left ? visible.minX : visible.maxX - size.width
        petView.setBubbleMode(edge: nil)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        mode = .idle
        clearEdgeState()
    }

    private func clearEdgeState() {
        bubbleTransition = nil
        snappedEdge = nil
        fullEdgeOrigin = nil
        edgeDeliveryDeadline = nil
        bubbleHoverStartedAt = nil
    }

    private func activeScreen() -> NSScreen {
        screen(containing: panel.frame)
    }

    private func screen(containing frame: CGRect) -> NSScreen {
        NSScreen.screens.max(by: {
            Self.intersectionArea($0.frame, frame) < Self.intersectionArea($1.frame, frame)
        }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
