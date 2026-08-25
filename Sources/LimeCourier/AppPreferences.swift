import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
    static let supportedSizes: [Double] = [120, 168, 224]
    static let supportedSpeeds: [Double] = [0.8, 1.0, 1.25]

    private enum Key {
        static let petSize = "petSize"
        static let autonomousEnabled = "pet.autonomousEnabled"
        static let mouseFollowEnabled = "pet.mouseFollowEnabled"
        static let legacyInteractionEnabled = "pet.interactionEnabled"
        static let edgeHideEnabled = "pet.edgeHideEnabled"
        static let alwaysOnTop = "pet.alwaysOnTop"
        static let animationSpeed = "pet.animationSpeed"
        static let selectedStandbyAction = "pet.selectedStandbyAction"
        static let legacySelectedAction = "pet.selectedAction"
        static let launchAtLogin = "launchAtLogin"
        static let petX = "petX"
        static let petY = "petY"
        static let hasPetPosition = "hasPetPosition"
    }

    private let defaults: UserDefaults

    @Published var petSize: Double {
        didSet { defaults.set(Self.normalizedSize(petSize), forKey: Key.petSize) }
    }
    @Published var autonomousEnabled: Bool {
        didSet { defaults.set(autonomousEnabled, forKey: Key.autonomousEnabled) }
    }
    @Published var mouseFollowEnabled: Bool {
        didSet { defaults.set(mouseFollowEnabled, forKey: Key.mouseFollowEnabled) }
    }
    @Published var edgeHideEnabled: Bool {
        didSet { defaults.set(edgeHideEnabled, forKey: Key.edgeHideEnabled) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }
    @Published var animationSpeed: Double {
        didSet { defaults.set(Self.normalizedSpeed(animationSpeed), forKey: Key.animationSpeed) }
    }
    @Published var selectedStandbyAction: PetSelectableAction {
        didSet { defaults.set(selectedStandbyAction.rawValue, forKey: Key.selectedStandbyAction) }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        petSize = Self.normalizedSize(defaults.object(forKey: Key.petSize) as? Double ?? 168)
        autonomousEnabled = defaults.object(forKey: Key.autonomousEnabled) as? Bool ?? true
        mouseFollowEnabled = defaults.object(forKey: Key.mouseFollowEnabled) as? Bool
            ?? defaults.object(forKey: Key.legacyInteractionEnabled) as? Bool
            ?? true
        edgeHideEnabled = defaults.object(forKey: Key.edgeHideEnabled) as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        animationSpeed = Self.normalizedSpeed(defaults.object(forKey: Key.animationSpeed) as? Double ?? 1)
        let storedStandbyAction = defaults.string(forKey: Key.selectedStandbyAction)
        let legacyStandbyAction = defaults.string(forKey: Key.legacySelectedAction)
        let savedStandbyAction = storedStandbyAction ?? legacyStandbyAction
        selectedStandbyAction = PetSelectableAction(rawValue: savedStandbyAction ?? "") ?? .sit
        if storedStandbyAction == nil,
           let migratedAction = PetSelectableAction(rawValue: legacyStandbyAction ?? "") {
            defaults.set(migratedAction.rawValue, forKey: Key.selectedStandbyAction)
        }
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
    }

    var savedPetOrigin: CGPoint? {
        guard defaults.bool(forKey: Key.hasPetPosition) else { return nil }
        return CGPoint(x: defaults.double(forKey: Key.petX), y: defaults.double(forKey: Key.petY))
    }

    func savePetOrigin(_ origin: CGPoint) {
        defaults.set(origin.x, forKey: Key.petX)
        defaults.set(origin.y, forKey: Key.petY)
        defaults.set(true, forKey: Key.hasPetPosition)
    }

    func resetPetOrigin() {
        defaults.removeObject(forKey: Key.petX)
        defaults.removeObject(forKey: Key.petY)
        defaults.set(false, forKey: Key.hasPetPosition)
    }

    static func normalizedSize(_ value: Double) -> Double {
        supportedSizes.min(by: { abs($0 - value) < abs($1 - value) }) ?? 168
    }

    static func normalizedSpeed(_ value: Double) -> Double {
        supportedSpeeds.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1
    }

    private func updateLaunchAtLogin() {
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update launch-at-login: %@", error.localizedDescription)
        }
    }
}
