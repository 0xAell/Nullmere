import CoreGraphics
import NullmereLand
import NullmereLive
import NullmereLiveStage
import NullmereSound

/// The rebuilt realm heard: each piece of news its cue as it comes, what is
/// chosen and what the realm refuses each its own, and the world about
/// where the player looks its beds of sound, each second.
enum LiveSounds {
    /// The cue a piece of news is told with.
    static func cue(for told: LiveTold) -> SoundCue {
        switch told {
        case .raised: return .complete
        case .trained: return .muster
        case .healed: return .rise
        case .learnt: return .lore
        case .home: return .stand
        case .won: return .triumph
        case .lost: return .dread
        case .report: return .watch
        case .letter: return .envoy
        case .helped: return .accord
        case .rally: return .horn
        case .gift: return .coin
        case .threat: return .dread
        }
    }

    /// The cues of the news told after the last heard, in the order told;
    /// all of it where none was heard before.
    static func cues(for news: [LiveNews], after last: Int?) -> [SoundCue] {
        news.filter { $0.id > (last ?? 0) }.map { cue(for: $0.kind) }
    }

    /// Sets the beds of sound to what is heard: the towns and their works,
    /// the lake's edge, the fights and the barrows. No wood burns in the
    /// rebuilt realm, and its wind blows as it always does.
    @MainActor
    static func apply(_ scape: LiveSoundscape, to ambience: Ambience) {
        ambience.setTown(level: scape.town.level, pan: scape.town.pan)
        ambience.setShore(level: scape.shore.level, pan: scape.shore.pan)
        ambience.setDin(level: scape.din.level, pan: scape.din.pan)
        ambience.setHost(scape.host)
        ambience.setKeening(level: scape.keening.level, pan: scape.keening.pan)
        ambience.setBlaze(level: 0, pan: 0)
        ambience.setAir(strength: 1, pan: 0)
        ambience.setThreshing(scape.share(.granary))
        ambience.setSawing(scape.share(.sawpit))
        ambience.setQuarrying(scape.share(.quarry))
        ambience.setRaking(scape.share(.saltworks))
        ambience.setDrilling(scape.share(.musterHall))
        ambience.setGrinding(scape.share(.infirmary))
        ambience.setReading(scape.share(.archive))
        ambience.setForging(scape.share(.forge))
        ambience.setPosting(scape.share(.wayhouse))
        ambience.setBurning(scape.share(.beacon))
        ambience.setChiselling(scape.share(.lodge))
    }

    /// Hears the world about where the player looks each second, in a view
    /// of a size, while it is shown; silent once it is not.
    @MainActor
    static func listen(to session: LiveSession, in size: CGSize) async {
        while !Task.isCancelled {
            if let ambience = RealmSound.current?.ambience {
                apply(session.soundscape(in: size), to: ambience)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        if let ambience = RealmSound.current?.ambience {
            apply(LiveSoundscape(), to: ambience)
        }
    }
}
