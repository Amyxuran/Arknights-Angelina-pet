import Foundation
import Testing
@testable import LimeCourier

@Suite("Desktop pet preferences")
@MainActor
struct PetPreferencesTests {
    @Test("Pure pet defaults enable core behavior")
    func defaults() {
        let name = "PetPreferencesTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.petSize == 168)
        #expect(preferences.animationSpeed == 1)
        #expect(preferences.selectedStandbyAction == .sit)
        #expect(preferences.autonomousEnabled)
        #expect(preferences.mouseFollowEnabled)
        #expect(preferences.edgeHideEnabled)
        #expect(preferences.alwaysOnTop)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Legacy values normalize to menu presets")
    func normalization() {
        #expect(AppPreferences.normalizedSize(160) == 168)
        #expect(AppPreferences.normalizedSize(110) == 120)
        #expect(AppPreferences.normalizedSize(230) == 224)
        #expect(AppPreferences.normalizedSpeed(0.9) == 0.8)
        #expect(AppPreferences.normalizedSpeed(1.2) == 1.25)
    }

    @Test("Position persistence can be reset")
    func positionPersistence() {
        let name = "PetPreferencesTests.position.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = AppPreferences(defaults: defaults)
        preferences.savePetOrigin(CGPoint(x: 90, y: 140))
        #expect(preferences.savedPetOrigin == CGPoint(x: 90, y: 140))
        preferences.resetPetOrigin()
        #expect(preferences.savedPetOrigin == nil)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Legacy interaction preference migrates to mouse follow")
    func legacyMouseFollowMigration() {
        let name = "PetPreferencesTests.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(false, forKey: "pet.interactionEnabled")
        let preferences = AppPreferences(defaults: defaults)
        #expect(!preferences.mouseFollowEnabled)
        preferences.mouseFollowEnabled = true
        #expect(defaults.bool(forKey: "pet.mouseFollowEnabled"))
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Standby action selection persists")
    func standbyActionPersistence() {
        let name = "PetPreferencesTests.action.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = AppPreferences(defaults: defaults)
        preferences.selectedStandbyAction = .dive
        let restored = AppPreferences(defaults: defaults)
        #expect(restored.selectedStandbyAction == .dive)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Legacy selected action migrates to standby selection")
    func legacyActionMigration() {
        let name = "PetPreferencesTests.legacyAction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(PetSelectableAction.read.rawValue, forKey: "pet.selectedAction")
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.selectedStandbyAction == .read)
        #expect(defaults.string(forKey: "pet.selectedStandbyAction") == PetSelectableAction.read.rawValue)
        defaults.removePersistentDomain(forName: name)
    }
}
