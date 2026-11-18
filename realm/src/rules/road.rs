//! The Barrow Road: a ladder of stages, each a host of the Unquiet that
//! leans on one kind of soldier. A player walks the next stage with
//! soldiers of their city, as many as its host has at most, under one of
//! their commanders or under none. The fight is fought as any other, but
//! the road's dead are shades: none of the player's soldiers are lost, and
//! a host that turns them back stands as it stood. Each stage cleared the
//! first time gives goods, every fifth an item besides, and the commander
//! who led them has seen as much as fell before them. Between walks their
//! soldiers rest a minute.

use super::{asking, city_of, give, goods, mastery, realm, report, seen_by, set_goods, settle, with_leading, Mastery, Refusal, MOST_ROUNDS};
use super::{commanding, fight_learned, leader_for, march::wanted, Asked};
use crate::catalog::{self, Troops, Unit};
use crate::rows::{Db, Report, Road, Stage};
use crate::store::Table;

/// Writes the road's stages out as rows, for clients to show, as the
/// realm opens.
pub fn write_stages(db: &mut impl Db) {
    for id in 1..=catalog::ROAD_STAGES {
        let (host, most) = catalog::road_host(id);
        let count = |kind: Troops| host.iter().filter(|unit| unit.kind == kind).map(|unit| unit.count).sum();
        let (gives, item) = catalog::road_gives(id);
        let (item, items) = item.map(|(item, count)| (item as u8, count)).unwrap_or((0, 0));
        db.insert(Stage {
            id,
            tier: host[0].tier,
            spearmen: count(Troops::Spearmen),
            archers: count(Troops::Archers),
            riders: count(Troops::Riders),
            most,
            grain: gives.grain,
            timber: gives.timber,
            stone: gives.stone,
            moonsalt: gives.moonsalt,
            item,
            items,
        });
    }
}

/// How far a player has come along the road.
pub fn road_of(db: &impl Db, player: u64) -> Road {
    Table::<Road>::get(db, player).unwrap_or(Road { player, cleared: 0, walked: 0 })
}

/// A player walks the next stage of the road with the soldiers asked, led
/// by a commander of theirs (0 for none). Whether they cleared it, and
/// which stage it was.
pub fn walk_road(db: &mut impl Db, player: u64, asked: &[Asked], leader: u64) -> Result<(bool, u64), Refusal> {
    asking(db, player)?;
    let city = city_of(db, player)?;
    let kept = Table::<Road>::get(db, player);
    let mut road = kept.clone().unwrap_or(Road { player, cleared: 0, walked: 0 });
    if road.cleared >= catalog::ROAD_STAGES {
        return Err(Refusal::RoadWalked);
    }
    let now = db.now();
    let pace = realm(db).map(|realm| realm.pace).unwrap_or(1);
    let rested = road.walked + catalog::paced(catalog::ROAD_REST, pace);
    if kept.is_some() && now < rested {
        return Err(Refusal::RoadResting(rested - now));
    }
    let stage = road.cleared + 1;
    let (host, most) = catalog::road_host(stage);
    let wanted = wanted(db, city.id, asked)?;
    let fought: u64 = wanted.iter().map(|ask| ask.count).sum();
    if fought > most {
        return Err(Refusal::RoadNarrow(most));
    }
    let led = if leader == 0 { None } else { Some(leader_for(db, player, leader)?) };
    let learnt = match &led {
        Some(commander) => with_leading(mastery(db, city.id), commanding(db, commander)),
        None => mastery(db, city.id),
    };
    let mut army: Vec<Unit> = wanted.iter().filter_map(|ask| Troops::of(ask.kind).map(|kind| Unit { kind, tier: ask.tier, count: ask.count })).collect();
    army.sort_by_key(|unit| (std::cmp::Reverse(unit.tier), unit.kind as u8));
    let mut rolls: Vec<u64> = (0..2 * MOST_ROUNDS).map(|_| db.chance()).collect();
    let outcome = fight_learned(&army, &host, [learnt.against_the_unquiet(), Mastery::default()], 0, || rolls.pop().unwrap_or(0));
    let stood: u64 = host.iter().map(|unit| unit.count).sum();
    let fell: u64 = outcome.defenders_lost.iter().sum();

    let mut won = catalog::Goods::of(0, 0, 0, 0);
    let words = if outcome.won {
        road.cleared = stage;
        let (gives, item) = catalog::road_gives(stage);
        won = gives;
        let mut stock = settle(db, city.id)?;
        let more = goods(&stock).plus(gives);
        set_goods(&mut stock, more);
        db.update(stock);
        let mut words = format!("Your soldiers cleared stage {stage} of the Barrow Road: all {} of its Unquiet fell, and none of yours were lost. It gave {gives}", catalog::grouped(stood));
        if let Some((item, count)) = item {
            give(db, player, item, count);
            words.push_str(&format!(", and {count} × {}", item.name()));
        }
        if let Some(commander) = &led {
            seen_by(db, commander.id, fell * (1 + (stage - 1) / 6));
            words.push_str(&format!(". {} led them", commander.name));
        }
        words.push('.');
        words
    } else {
        format!(
            "Your soldiers were turned back at stage {stage} of the Barrow Road: {} of its {} Unquiet still stood. None of yours were lost; its host leans on {}.",
            catalog::grouped(stood - fell),
            catalog::grouped(stood),
            host[0].kind.name().to_lowercase()
        )
    };
    road.walked = now;
    if kept.is_some() {
        db.update(road);
    } else {
        db.insert(road);
    }
    report(
        db,
        Report {
            id: 0,
            player,
            at: now,
            kind: Report::ROAD,
            hex: city.hex,
            won: outcome.won,
            foe: stage,
            rounds: outcome.rounds,
            fought,
            wounded: 0,
            dead: 0,
            stood,
            fell,
            grain: won.grain,
            timber: won.timber,
            stone: won.stone,
            moonsalt: won.moonsalt,
            words,
            read: false,
        },
    );
    Ok((outcome.won, stage))
}
