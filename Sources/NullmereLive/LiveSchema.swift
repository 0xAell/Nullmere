import Foundation
import NullmereRealm

/// The realm's tables and views as a client watches them: the module in
/// `realm/` declares them, and each list here gives one's columns in the
/// order the module has them, which is the order a transaction's rows
/// come in. `LiveSchemaTests` holds every list to the module's source.
public enum LiveSchema {
    static let player = ["id", "name_key", "name", "joined", "online", "seen"]
    static let city = ["id", "owner", "hex", "name", "keep", "power", "founded", "builders", "shield"]

    /// Every table and view a client reads, with the column that tells
    /// its rows apart. The views show a caller their own rows.
    public static let tables: [String: SubscriptionMirror.Table] = [
        "realm": .init(columns: ["id", "seed", "opened", "pace", "joining_minute", "joined_in_minute", "radius"], key: "id"),
        "player": .init(columns: player, key: "id"),
        "land": .init(columns: ["chunk", "ground"], key: "chunk"),
        "place": .init(columns: ["hex", "kind", "id"], key: "hex"),
        "blueprint": .init(columns: ["id", "building", "level", "name", "grain", "timber", "stone", "moonsalt", "seconds", "grain_hourly",
                                     "timber_hourly", "stone_hourly", "moonsalt_hourly", "opens_at", "needs_building", "needs_level", "power"],
                           key: "id"),
        "soldier": .init(columns: ["id", "kind", "tier", "name", "attack", "defence", "health", "pace", "load", "power", "grain", "timber",
                                   "stone", "moonsalt", "millis", "building", "needs_level"], key: "id"),
        "city": .init(columns: city, key: "id"),
        "site": .init(columns: ["id", "hex", "kind", "level", "left", "gatherer"], key: "id"),
        "barrow": .init(columns: ["id", "hex", "level", "fighter"], key: "id"),
        "alliance": .init(columns: ["id", "name_key", "tag_key", "name", "tag", "leader", "founded", "members", "open", "words"], key: "id"),
        "member": .init(columns: ["player", "alliance", "rank", "joined"], key: "player"),
        "realm_chat": .init(columns: ["id", "player", "name", "at", "words"], key: "id"),
        "study": .init(columns: ["id", "topic", "level", "name", "words", "each", "grain", "timber", "stone", "moonsalt", "seconds", "needs_level",
                                 "after_topic", "after_level"],
                       key: "id"),
        "task": .init(columns: ["step", "goal", "amount", "level", "words", "grain", "timber", "stone", "moonsalt", "brief_hastes", "hour_hastes",
                                "long_hastes", "tomes"], key: "step"),
        "march": .init(columns: ["id", "owner", "city", "kind", "state", "from", "to", "target", "departed", "arrives", "soldiers", "route",
                                 "timer", "leader"], key: "id"),
        "me": .init(columns: player, key: "id"),
        "my_city": .init(columns: city, key: "id"),
        "my_buildings": .init(columns: ["id", "city", "kind", "level"], key: "id"),
        "my_jobs": .init(columns: ["id", "city", "kind", "subject", "level", "amount", "started", "ends", "timer"], key: "id"),
        "my_stock": .init(columns: ["city", "grain", "timber", "stone", "moonsalt", "as_of", "grain_hourly", "timber_hourly", "stone_hourly",
                                    "moonsalt_hourly", "grain_part", "timber_part", "stone_part", "moonsalt_part", "holds"], key: "city"),
        "my_troops": .init(columns: ["id", "city", "kind", "tier", "ready", "wounded"], key: "id"),
        "my_squads": .init(columns: ["id", "march", "kind", "tier", "count", "wounded"], key: "id"),
        "my_hauls": .init(columns: ["march", "owner", "grain", "timber", "stone", "moonsalt"], key: "march"),
        "my_hunt": .init(columns: ["player", "energy", "as_of", "most", "point_millis", "cleared"], key: "player"),
        "my_reports": .init(columns: ["id", "player", "at", "kind", "hex", "won", "foe", "rounds", "fought", "wounded", "dead", "stood", "fell",
                                      "grain", "timber", "stone", "moonsalt", "words", "read"], key: "id"),
        "my_alliance_chat": .init(columns: ["id", "alliance", "player", "name", "at", "words"], key: "id"),
        "my_applicants": .init(columns: ["player", "alliance", "name", "at"], key: "player"),
        "my_progress": .init(columns: ["player", "step"], key: "player"),
        "my_lore": .init(columns: ["id", "city", "topic", "level"], key: "id"),
        "my_commanders": .init(columns: ["id", "owner", "name", "way", "level", "seen", "march", "person", "gift", "sigils"], key: "id"),
        "duty": .init(columns: ["deed", "asks", "marks", "words"], key: "deed"),
        "chest": .init(columns: ["id", "marks", "grain", "timber", "stone", "moonsalt", "brief_hastes", "hour_hastes", "long_hastes", "peaces"], key: "id"),
        "grace": .init(columns: ["level", "points", "sooner"], key: "level"),
        "ware": .init(columns: ["item", "name", "words", "seconds", "kind"], key: "item"),
        "trial": .init(columns: ["id", "name", "words", "every", "lasts", "opens"], key: "id"),
        "prize": .init(columns: ["id", "trial", "place", "points", "grain", "timber", "stone", "moonsalt", "brief_hastes", "hour_hastes",
                                 "long_hastes", "peaces"], key: "id"),
        "standing": .init(columns: ["id", "contest_round", "player", "trial", "round", "points", "at", "claimed"], key: "id"),
        "laurel": .init(columns: ["id", "trial", "place", "grain", "timber", "stone", "moonsalt", "brief_hastes", "hour_hastes", "long_hastes",
                                  "peaces"], key: "id"),
        "spire": .init(columns: ["alliance", "name", "season", "stage", "rises_at", "timer", "grain", "timber", "stone", "moonsalt"], key: "alliance"),
        "season": .init(columns: ["number", "began", "ends", "victor", "victor_name", "won_at"], key: "number"),
        "ward": .init(columns: ["id", "alliance", "hex", "raised_by", "stands_at"], key: "id"),
        "learning": .init(columns: ["id", "alliance", "topic", "level", "rises_at", "timer", "grain", "timber", "stone"], key: "id"),
        "gate": .init(columns: ["id", "hex", "holder", "holder_name", "taken_at", "fighter"], key: "id"),
        "pact": .init(columns: ["id", "first", "second", "terms", "began", "ends"], key: "id"),
        "title": .init(columns: ["title", "holder", "name", "since"], key: "title"),
        "fame": .init(columns: ["player", "kills", "felled", "dead"], key: "player"),
        "my_daily": .init(columns: ["player", "day", "trained", "gathered", "cleared", "begun", "hastened", "opened"], key: "player"),
        "my_favour": .init(columns: ["player", "points", "level"], key: "player"),
        "my_satchel": .init(columns: ["id", "player", "item", "count"], key: "id"),
        "my_tallies": .init(columns: ["id", "player", "trial", "round", "points", "claimed"], key: "id"),
        "my_link": .init(columns: ["code", "player", "letters", "expires"], key: "code"),
        "my_devices": .init(columns: ["number", "name", "here", "current"], key: "number"),
        "my_rallies": .init(columns: ["id", "alliance", "caller", "name", "barrow", "city", "hex", "level", "sets_out", "state", "armies",
                                      "soldiers"], key: "id"),
        "my_musters": .init(columns: ["march", "rally", "player", "arrived"], key: "march"),
        "my_pleas": .init(columns: ["job", "alliance", "asker", "name", "work", "helped", "most"], key: "job"),
        "my_helps": .init(columns: ["id", "job", "player"], key: "id"),
        "my_gift": .init(columns: ["player", "season", "given"], key: "player"),
        "my_skills": .init(columns: ["id", "commander", "owner", "talent", "points"], key: "id"),
        "my_bonds": .init(columns: ["commander", "owner", "partner"], key: "commander"),
        "my_keeper": .init(columns: ["player", "commander"], key: "player"),
        "my_letters": .init(columns: ["id", "sender", "receiver", "name", "words", "at", "read"], key: "id"),
        "pattern": .init(columns: ["piece", "name", "slot", "grade", "words", "iron", "leather", "bone", "silver", "grain", "timber", "stone", "moonsalt",
                                   "forge_level"], key: "piece"),
        "my_gear": .init(columns: ["id", "owner", "piece", "commander"], key: "id"),
        "my_boons": .init(columns: ["id", "player", "giver", "level", "grain", "timber", "stone", "expires", "timer"], key: "id"),
        "cairn": .init(columns: ["id", "hex", "level"], key: "id"),
        "my_finds": .init(columns: ["id", "player", "cairn", "at"], key: "id"),
        "price": .init(columns: ["item", "honour"], key: "item"),
        "my_honour": .init(columns: ["player", "honour", "day", "from_help"], key: "player"),
        "my_envoys": .init(columns: ["id", "sender", "receiver", "name", "terms", "days", "sent_at"], key: "id"),
        "my_prisoners": .init(columns: ["commander", "owner", "captor", "name", "grain", "timber", "stone", "freed_at", "timer"], key: "commander"),
        "my_petitions": .init(columns: ["asker", "alliance", "name", "grain", "timber", "stone", "moonsalt", "sent_grain", "sent_timber", "sent_stone",
                                        "sent_moonsalt", "made_at"], key: "asker"),
    ]

    /// The view each of the caller's own tables is read through.
    public static let views: [String: String] = [
        "me": "player", "my_city": "city", "my_buildings": "building", "my_jobs": "job", "my_stock": "stock", "my_troops": "troop",
        "my_squads": "squad", "my_hauls": "haul", "my_hunt": "hunt", "my_reports": "report", "my_alliance_chat": "alliance_chat",
        "my_applicants": "applicant", "my_progress": "progress", "my_lore": "lore", "my_commanders": "commander",
        "my_daily": "daily", "my_favour": "favour", "my_satchel": "satchel",
        "my_tallies": "tally", "my_rallies": "rally", "my_musters": "muster", "my_pleas": "plea", "my_helps": "helper", "my_gift": "gift",
        "my_skills": "skill", "my_bonds": "bond", "my_keeper": "keeper", "my_envoys": "envoy", "my_prisoners": "prisoner", "my_petitions": "petition",
        "my_letters": "letter", "my_gear": "gear", "my_boons": "boon", "my_finds": "find", "my_honour": "honour",
        "my_link": "link",
    ]

    /// The queries that watch all of them.
    public static let queries: [String] = tables.keys.sorted().map { "SELECT * FROM \($0)" }
}
