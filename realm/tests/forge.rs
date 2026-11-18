//! The Forge over a store kept in memory: what it makes written out, a
//! piece made from materials and goods at a Forge high enough, worn by a
//! commander and adding to what they bring, and what the barrows yield.

use realm::catalog::{self, Building as Kind, Goods, Item, Leading, Piece, Slot};
use realm::rows::{Building, Gear, Pattern, Prisoner, Stock};
use realm::rules::{self, Refusal};
use realm::store::{Mem, Seconds, Table};

const START: Seconds = 3_000_000;

fn wait(db: &mut Mem, seconds: Seconds) {
    let to = db.clock + seconds;
    db.advance(to, rules::fire);
}

/// Ada with goods enough, and Bryn beside her.
fn realm() -> (Mem, u64, u64) {
    let mut db = Mem::new(START, 5);
    rules::open(&mut db, 7, 1, 48);
    let ada = db.call(|db| rules::join(db, "Ada")).unwrap().id;
    let bryn = db.call(|db| rules::join(db, "Bryn")).unwrap().id;
    let city = rules::city_of(&db, ada).unwrap();
    let mut stock = rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock);
    (stock.grain, stock.timber, stock.stone, stock.moonsalt, stock.holds) = (500_000, 500_000, 500_000, 50_000, 10_000_000);
    db.update(stock);
    (db, ada, bryn)
}

fn forge_at(db: &mut Mem, player: u64, level: u32) {
    let city = rules::city_of(db, player).unwrap();
    match rules::building_of(db, city.id, Kind::Forge) {
        Some(mut forge) => {
            forge.level = level;
            db.update(forge);
        }
        None => {
            db.insert(Building { id: 0, city: city.id, kind: Kind::Forge as u8, level });
        }
    }
}

#[test]
fn what_the_forge_makes_is_written_out() {
    let (db, _, _) = realm();
    let patterns = Table::<Pattern>::all(&db);
    assert_eq!(patterns.len(), 12);
    let sword = Table::<Pattern>::get(&db, Piece::IronSword as u64).unwrap();
    assert_eq!((sword.name.as_str(), sword.slot, sword.grade, sword.forge_level), ("Iron sword", Slot::Weapon as u8, 1, 1));
    assert_eq!((sword.iron, sword.leather, sword.bone, sword.silver, sword.timber, sword.stone), (4, 4, 0, 0, 5_000, 5_000));
    assert_eq!(sword.words, "Everyone its wearer leads strikes 3% harder.");
    let greaves = Table::<Pattern>::get(&db, Piece::SilverGreaves as u64).unwrap();
    assert_eq!((greaves.slot, greaves.grade, greaves.forge_level, greaves.silver), (Slot::Boots as u8, 3, 16, 6));
    assert_eq!(greaves.words, "Its wearer's army marches 12% faster.");
    for piece in Piece::ALL {
        assert_eq!(Piece::of(piece as u8), Some(piece));
        assert_ne!(piece.leading(), Leading::default(), "{} adds something", piece.name());
    }
    assert_eq!(Piece::of(0), None);
    assert_eq!(Piece::of(13), None);
    assert_eq!(Item::Iron.words(), "Worked at the Forge into gear for your commanders. The barrows of the Unquiet yield it.");
}

#[test]
fn a_piece_is_made_at_a_forge_high_enough_from_materials_and_goods() {
    let (mut db, ada, _) = realm();
    let sword = Piece::IronSword as u8;
    // No Forge, a Forge too low, no materials: refused, and nothing paid.
    assert_eq!(db.call(|db| rules::forge(db, ada, sword)), Err(Refusal::NeedsOther(Kind::Forge, 1)));
    forge_at(&mut db, ada, 1);
    assert_eq!(db.call(|db| rules::forge(db, ada, Piece::SteelSword as u8)), Err(Refusal::NeedsOther(Kind::Forge, 8)));
    assert_eq!(db.call(|db| rules::forge(db, ada, 99)), Err(Refusal::NoSuchPiece));
    assert_eq!(db.call(|db| rules::forge(db, ada, sword)), Err(Refusal::ShortOfMaterials("4 iron and 4 leather".into())));
    assert_eq!(Refusal::ShortOfMaterials("4 iron and 4 leather".into()).to_string(), "You need 4 iron and 4 leather more.");
    rules::give(&mut db, ada, Item::Iron, 5);
    rules::give(&mut db, ada, Item::Leather, 2);
    assert_eq!(db.call(|db| rules::forge(db, ada, sword)), Err(Refusal::ShortOfMaterials("2 leather".into())));
    rules::give(&mut db, ada, Item::Leather, 2);

    // Made: the materials and the goods taken, the piece hers, worn by no one.
    let city = rules::city_of(&db, ada).unwrap();
    let before = rules::goods(&rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock));
    let made = db.call(|db| rules::forge(db, ada, sword)).unwrap();
    assert_eq!((made.owner, made.piece, made.commander), (ada, sword, 0));
    assert_eq!((rules::held(&db, ada, Item::Iron), rules::held(&db, ada, Item::Leather)), (1, 0));
    let after = rules::goods(&rules::grown(&Table::<Stock>::get(&db, city.id).unwrap(), db.clock));
    assert_eq!(before.minus(after), Goods::of(0, 5_000, 5_000, 0));
    // A material is not used on a work, nor kept as peace.
    assert_eq!(db.call(|db| rules::use_item(db, ada, Item::Iron as u8, 1)), Err(Refusal::AtTheForge));
    assert_eq!(db.call(|db| rules::keep_peace(db, ada, Item::Iron as u8)), Err(Refusal::AtTheForge));
    assert_eq!(Refusal::AtTheForge.to_string(), "That is worked at the Forge into gear.");
}

#[test]
fn a_commander_wears_one_piece_in_each_place_and_leads_the_better_for_it() {
    let (mut db, ada, bryn) = realm();
    forge_at(&mut db, ada, 16);
    for item in Item::MATERIALS {
        rules::give(&mut db, ada, item, 100);
    }
    let make = |db: &mut Mem, piece: Piece| {
        wait(db, 1);
        db.call(|db| rules::forge(db, ada, piece as u8)).unwrap()
    };
    let (iron, silver, cap) = (make(&mut db, Piece::IronSword), make(&mut db, Piece::SilverSword), make(&mut db, Piece::LeatherCap));
    let captain = rules::commanders_of(&db, ada)[0].clone();
    let bare = rules::commanding(&db, &captain);

    // Worn: what it adds is the commander's to lead with.
    db.call(|db| rules::equip(db, ada, iron.id, captain.id)).unwrap();
    let armed = rules::commanding(&db, &captain);
    assert_eq!(armed.strikes.iter().zip(bare.strikes).map(|(now, was)| now - was).collect::<Vec<_>>(), vec![3, 3, 3, 3]);
    // Another weapon takes the first's place; a helm goes beside it.
    wait(&mut db, 1);
    db.call(|db| rules::equip(db, ada, silver.id, captain.id)).unwrap();
    assert_eq!(Table::<Gear>::get(&db, iron.id).unwrap().commander, 0, "the iron sword comes off");
    wait(&mut db, 1);
    db.call(|db| rules::equip(db, ada, cap.id, captain.id)).unwrap();
    let led = rules::commanding(&db, &captain);
    assert_eq!(led.strikes[0] - bare.strikes[0], 9);
    assert_eq!(led.shields - bare.shields, 2);
    // Taken off, it adds nothing.
    wait(&mut db, 1);
    db.call(|db| rules::unequip(db, ada, silver.id)).unwrap();
    assert_eq!(rules::commanding(&db, &captain).strikes, bare.strikes);

    // Only her own gear on her own commanders, and none on one held prisoner.
    let theirs = rules::commanders_of(&db, bryn)[0].clone();
    wait(&mut db, 1);
    assert_eq!(db.call(|db| rules::equip(db, bryn, iron.id, theirs.id)), Err(Refusal::NoSuchGear));
    assert_eq!(db.call(|db| rules::equip(db, ada, iron.id, theirs.id)), Err(Refusal::NoSuchCommander));
    assert_eq!(db.call(|db| rules::unequip(db, bryn, iron.id)), Err(Refusal::NoSuchGear));
    db.insert(Prisoner { commander: captain.id, owner: ada, captor: bryn, name: captain.name.clone(), grain: 0, timber: 0, stone: 0, freed_at: db.clock + 100, timer: 0 });
    assert_eq!(db.call(|db| rules::equip(db, ada, iron.id, captain.id)), Err(Refusal::HeldPrisoner(captain.name.clone())));
}

#[test]
fn a_barrow_yields_a_material_for_each_level_and_silver_only_from_the_tenth() {
    for level in [1, 5, 9, 12, 25] {
        let mut roll = 0u64;
        let yielded = catalog::spoils_of(level, || {
            roll += 7;
            roll
        });
        assert_eq!(yielded.iter().sum::<u64>(), level as u64, "level {level}: {yielded:?}");
        if level < 10 {
            assert_eq!(yielded[3], 0, "no silver from a barrow below the tenth level");
        }
    }
    let mut roll = 0u64;
    assert!(catalog::spoils_of(25, || {
        roll += 1;
        roll
    })[3] > 0, "silver from the strongest");
    assert_eq!(rules::materials_words([3, 0, 1, 0]), "3 iron and 1 bone");
    assert_eq!(rules::materials_words([1, 2, 3, 4]), "1 iron, 2 leather, 3 bone and 4 silver");
}
