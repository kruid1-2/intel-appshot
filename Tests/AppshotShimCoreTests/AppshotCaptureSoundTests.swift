import Foundation
import Testing
@testable import AppshotShimCore

@Test @MainActor
func appshotSoundDefaultsOnAndReadsSwitchAtEachOpening() {
    let name = "appshot-sound-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    var plays = 0
    let sound = AppshotCaptureSound(defaults: defaults) { plays += 1 }
    sound.playIfEnabled()
    #expect(plays == 1)
    defaults.set(false, forKey: "appshotSoundEnabled")
    sound.playIfEnabled()
    #expect(plays == 1)
    defaults.set(true, forKey: "appshotSoundEnabled")
    sound.playIfEnabled()
    #expect(plays == 2)
    defaults.set("invalid", forKey: "appshotSoundEnabled")
    sound.playIfEnabled()
    #expect(plays == 3)
}
