import Foundation
import LauncherKit
import NullmereCore
import Observation

/// The window's sound, apart from any game: the night about the lake, the
/// title theme over the launcher and the realm's score (`Ambience`),
/// whether sound and music play, and how loud, as this Mac keeps them. The
/// launcher's Music and the realm's are one choice.
@MainActor
@Observable
public final class RealmSound {
    public let ambience: Ambience
    /// The launcher, told when music is turned on or off here.
    @ObservationIgnored public weak var display: LauncherModel?

    /// The sound the window opened with, for the app's last moments.
    public private(set) static weak var current: RealmSound?

    /// `sound` overrides the saved choice; tests keep the window silent.
    public init(sound: Bool? = nil) {
        let on = sound ?? (UserDefaults.standard.object(forKey: RealmSound.soundKey) as? Bool ?? true)
        isSoundOn = on
        ambience = Ambience(enabled: on)
        ambience.effectsVolume = Float(RealmSound.storedVolume("volume.effects"))
        ambience.ambienceVolume = Float(RealmSound.storedVolume("volume.ambience"))
        ambience.musicVolume = Float(RealmSound.storedVolume("volume.music"))
        ambience.isMusicOn = isMusicOn
        RealmSound.current = self
    }

    static let soundKey = "sound.enabled"
    static let musicKey = "music.enabled"

    public var isSoundOn: Bool {
        didSet {
            ambience.isEnabled = isSoundOn
            UserDefaults.standard.set(isSoundOn, forKey: RealmSound.soundKey)
        }
    }

    public var isMusicOn: Bool = UserDefaults.standard.object(forKey: "music.enabled") as? Bool ?? true {
        didSet {
            ambience.isMusicOn = isMusicOn
            UserDefaults.standard.set(isMusicOn, forKey: RealmSound.musicKey)
            display?.noteMusic(isMusicOn)
        }
    }

    /// How loud the cues, the night and the score play, each from 0 to 1,
    /// as last set.
    static func storedVolume(_ key: String) -> Double {
        min(max(UserDefaults.standard.object(forKey: key) as? Double ?? 1, 0), 1)
    }

    /// The lake whose title theme plays over the launcher: the one the
    /// player's realm last lay on, the Nullmere before any.
    public static var lastLake: Lake {
        UserDefaults.standard.string(forKey: lakeKey).flatMap(Lake.init(rawValue:)) ?? .round
    }

    static let lakeKey = "lake.last"

    /// Over the launcher: the title theme of the last lake, with the night
    /// about it.
    public func playTitle() {
        ambience.titleLake = RealmSound.lastLake
        ambience.start()
    }

    /// Within the realm: its own score.
    public func playRealm() {
        ambience.titleLake = nil
        ambience.start()
    }
}
