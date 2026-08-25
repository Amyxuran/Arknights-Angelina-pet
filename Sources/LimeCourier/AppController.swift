import AppKit

@MainActor
final class AppController {
    let preferences: AppPreferences
    let petWindow: PetWindowController
    private let statusMenu: StatusMenuController

    init() {
        let preferences = AppPreferences()
        let petWindow = PetWindowController(preferences: preferences)
        self.preferences = preferences
        self.petWindow = petWindow
        statusMenu = StatusMenuController(preferences: preferences)
        wireActions()
        petWindow.show()
        runVisualQAIfRequested()
    }

    func prepareToTerminate() {
        preferences.savePetOrigin(petWindow.persistedOrigin)
    }

    private func wireActions() {
        petWindow.contextMenuProvider = { [weak self] in
            self?.statusMenu.makeContextMenu() ?? NSMenu()
        }
        petWindow.onStateChanged = { [weak self] in self?.statusMenu.refresh() }
        statusMenu.isPetVisible = { [weak self] in self?.petWindow.isVisible ?? false }
        statusMenu.petStatus = { [weak self] in self?.petWindow.statusTitle ?? "休息中 · 坐坐" }
        statusMenu.onTogglePet = { [weak self] in
            guard let self else { return }
            self.petWindow.isVisible ? self.petWindow.hide() : self.petWindow.show()
        }
        statusMenu.onResetPosition = { [weak self] in self?.petWindow.resetPosition() }
        statusMenu.onQuit = { NSApp.terminate(nil) }
        statusMenu.refresh()
    }

    private func runVisualQAIfRequested() {
        guard let directoryPath = ProcessInfo.processInfo.environment["LIME_COURIER_QA_DIR"] else { return }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let originalOrigin = petWindow.frame.origin
                try await snapshot("00-idle", asset: "坐坐", in: directory)
                try await snapshot("01-hover-photo", asset: "拍照", in: directory)
                try await snapshot("02-single-click", asset: "纸飞机", in: directory)
                try await snapshot("03-double-click", asset: "购物", in: directory)
                petWindow.playAssetForQA("海边")
                petWindow.showLongPressEffectForQA()
                try await Task.sleep(nanoseconds: 260_000_000)
                try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("04-long-press.png"))
                try await snapshot("05-drag-left", asset: "骑行", mirrored: true, in: directory)
                try await snapshot("06-drag-right", asset: "骑行", mirrored: false, in: directory)
                try await snapshot("07-delivery-left", asset: "送货", mirrored: false, in: directory)
                try await snapshot("08-delivery-right", asset: "送货", mirrored: true, in: directory)
                petWindow.restoreAfterQA(origin: originalOrigin)
                petWindow.showBubbleForQA(edge: .left)
                try await Task.sleep(nanoseconds: 250_000_000)
                try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("09-edge-bubble-left.png"))
                petWindow.restoreAfterQA(origin: originalOrigin)
                petWindow.showBubbleForQA(edge: .right)
                try await Task.sleep(nanoseconds: 250_000_000)
                try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("10-edge-bubble-right.png"))
                petWindow.restoreAfterQA(origin: originalOrigin)
                petWindow.showBubbleTransitionForQA(edge: .left, rawProgress: 0.52)
                try await Task.sleep(nanoseconds: 120_000_000)
                try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("11-edge-suction-left.png"))
                petWindow.restoreAfterQA(origin: originalOrigin)
                petWindow.showBubbleTransitionForQA(edge: .right, rawProgress: 0.52)
                try await Task.sleep(nanoseconds: 120_000_000)
                try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("12-edge-suction-right.png"))
                petWindow.restoreAfterQA(origin: originalOrigin)
                let originalStandbyAction = preferences.selectedStandbyAction
                preferences.selectedStandbyAction = .dive
                try await Task.sleep(nanoseconds: 250_000_000)
                try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("13-selected-standby.png"))

                let report: [String: Any] = [
                    "pureDesktopPet": true,
                    "screenCaptureUsageDescriptionPresent": false,
                    "mouseFollowLabel": "鼠标追随",
                    "standbyActionOptions": PetSelectableAction.allCases.map(\.rawValue),
                    "selectedStandbyActionForQA": preferences.selectedStandbyAction.rawValue,
                    "bubbleAbsorptionDuration": PetInteractionConfiguration.bubbleAbsorptionDuration,
                    "bubbleSuctionMidpoint": PetBehaviorPolicy.bubbleSuctionProgress(0.52),
                    "asset": petWindow.animationAssetForQA,
                    "mirrored": petWindow.animationMirroredForQA,
                    "bubble": petWindow.isBubbleForQA,
                    "size": Double(petWindow.frame.width)
                ]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("qa-report.json"), options: .atomic)
                preferences.selectedStandbyAction = originalStandbyAction
                petWindow.restoreAfterQA(origin: originalOrigin)
            } catch {
                NSLog("Visual QA failed: %@", error.localizedDescription)
            }
            NSApp.terminate(nil)
        }
    }

    private func snapshot(_ name: String, asset: String, mirrored: Bool = false, in directory: URL) async throws {
        petWindow.playAssetForQA(asset, mirrored: mirrored)
        try await Task.sleep(nanoseconds: 260_000_000)
        try petWindow.writeVisualSnapshot(to: directory.appendingPathComponent("\(name).png"))
    }
}
