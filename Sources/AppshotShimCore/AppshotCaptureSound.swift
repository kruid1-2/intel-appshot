import Foundation
import AudioToolbox
import OSLog

@MainActor
public final class AppshotCaptureSound {
    public static let shared = AppshotCaptureSound()
    private static let logger = Logger(subsystem: "com.openai.sky.CUAService", category: "AppshotSound")
    private let defaults: UserDefaults
    private let playback: () -> Void

    private convenience init() {
        let audio = AppshotSystemSound(url: Bundle.main.url(forResource: "Appshot", withExtension: "wav"))
        self.init(defaults: .standard) { audio.play() }
    }

    public init(defaults: UserDefaults, playback: @escaping () -> Void) {
        self.defaults = defaults
        self.playback = playback
    }

    public func playIfEnabled() {
        guard defaults.object(forKey: "appshotSoundEnabled") as? Bool ?? true else {
            Self.logger.info("sound-skipped disabled")
            return
        }
        playback()
    }
}

// Same system-sound API and resource as the recovered ARM Helper. No volume
// override, playback queue, completion wait, or application-specific throttle.
private final class AppshotSystemSound {
    private var id: SystemSoundID = 0
    private let logger = Logger(subsystem: "com.openai.sky.CUAService", category: "AppshotSound")

    init(url: URL?) {
        guard let url else {
            logger.error("sound-resource-missing")
            return
        }
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
        guard status == noErr else {
            logger.error("sound-create-failed status=\(status)")
            id = 0
            return
        }
        var isUISound: UInt32 = 1
        let propertyStatus = AudioServicesSetProperty(
            kAudioServicesPropertyIsUISound, UInt32(MemoryLayout.size(ofValue: id)),
            &id, UInt32(MemoryLayout.size(ofValue: isUISound)), &isUISound
        )
        logger.info("sound-created status=\(status) uiPropertyStatus=\(propertyStatus)")
        // Original passes completePlaybackIfAppDies=false: no override property.
    }

    func play() {
        guard id != 0 else { return }
        AudioServicesPlaySystemSound(id)
        logger.info("sound-play-issued")
    }

    deinit {
        if id != 0 { AudioServicesDisposeSystemSoundID(id) }
    }
}
