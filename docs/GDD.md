# Game Design Doc (draft v0.3)

**Title: TRUST ISSUES**: lots of *issues* to fix (rails, wheels, the train) and nobody can be *trusted* (the impostor)
**Engine:** Godot 4 (GDScript) · **Assets:** Tripo3D + Blender (see `VIDEO_METHOD.md`)
**Platform:** PC, **Steam** (friend invites through Steam lobbies)
**Players:** 1–5 online co-op · **Impostor:** 1 secret saboteur when there are 3–5 players
**Inspired by:** RV There Yet (vehicle co-op chaos + **art style**), Peak (co-op climbing), Raft (gather, build, repair, sea), Among Us (hidden impostor)

---

## 1. One-line pitch
A man's coffee date goes wrong when his girlfriend is kidnapped. He and his friends chase the kidnapper across the country
on an old coal train (**Chapter 1**), then across the sea on a raft they build themselves (**Chapter 2**).
**One of the friends is secretly working against them.**

## 2. Roles
| Role | Who | Goal |
|------|-----|------|
| **Host (the boyfriend)** | The player who creates the lobby | Rescue the girlfriend |
| **Friends (crew)** | Invited players | Help the host rescue her |
| **Impostor** | 1 random crew member (only with 3–5 players) | Plays like a normal crew member, but secretly chooses the kidnap and sabotages the crew so they all die |

- 1–2 players: no impostor. Pure co-op, and sabotage events happen randomly ("the world" sabotages).
- Only the impostor knows they're the impostor.

### Voting (Among Us style, with a twist)
- On the train there's a **meeting table**. Any player can go to it and call a **meeting**, then everyone votes for someone.
- **Each player gets 1 meeting call per checkpoint run** (the stretch between two stations). It resets at every station.
  The impostor also has one, so not calling one doesn't give them away.
- Meetings can happen any time during the run, whenever someone gets suspicious.
- The voted player is **not kicked**. They keep playing normally.
- **If the voted player was the impostor:** their sabotage abilities are **silently locked/frozen**.
- **If the vote hit an innocent:** nothing happens.
- Nobody is told the result, so **the crew never knows for sure whether they caught the impostor.**
  That keeps the paranoia going all game.
- *Default: a correct vote locks the impostor's sabotage until the end of the current chapter (tune in playtests).*

### Win and lose
- **Crew loses** when **all players are dead**.
- **Impostor's last-man choice:** if everyone else is dead and only the impostor is alive, the impostor chooses:
  - **Kill themself:** the game is lost, and the impostor wins.
  - **Revive the others** and keep playing innocent, staying hidden for a later chance.
- **Crew wins** by rescuing the girlfriend at the end of Chapter 2.

## 3. Story flow

### Act 1: The Date (intro, host playable)
- The host character gets ready, with animations, and walks to the coffee shop. Other players watch the intro from the lobby.
- **Kidnap scenario, one of 4:**
  1. **On the road:** strangers grab her on the way to the café.
  2. **In front of the store:** she's taken outside the shop.
  3. **The toilet:** at the date she says she needs the toilet, and someone takes her there.
  4. **At the table:** the host gets hit on the head, blacks out, and wakes up seeing her dragged away.
- **Who chooses:** the **impostor** secretly picks the scenario while the intro animation plays, with a timer.
  If the timer runs out, or there's no impostor, **the game picks randomly**.

### Act 2: Gather the crew
- The host phones his friends, and all players spawn and meet **in front of the café**.
- **Phone tracker:** the girlfriend's phone shows she's at the **train station**.
- The crew runs to the station. A **helicopter** lands and takes her away.
- The crew jumps on an old **coal train** to follow. The helicopter flies off screen.

### Chapter 1: The Train Chase
- Ride the train through **5 stations**. Each one is a **checkpoint**, and the game saves on arrival.
- Between stations: keep the train running, gather resources, repair the track, survive sabotage.
- Some routes are **locked** and need a key from a side quest (see 7).
- The train has a **locked container**. The crew doesn't know what's inside until Chapter 2: a boat engine, gasoline and boat tools.

### Chapter 2: The Sea (the yacht chase)
- At the last station the crew finds the **helicopter** near a **boat port** with the kidnapper's **big yacht**.
- The kidnapper **escapes out to sea** on the yacht.
- **The game changes from train to sea.** The crew opens the train's container (boat engine, gasoline, boat tools)
  and **builds a raft** (Raft-style), then chases the yacht.
- **Carried over:** gold, the crafting table and blueprints.
- **New impostor sabotages:** 🦈 shark, 🐟 piranhas, 🌊 tsunami, 🌪️ windstorm.
- Ending: reach the yacht and rescue her *(how the yacht finale plays: see 10)*.

## 4. Core loop: the train (Chapter 1)
```
Shovel coal → furnace heats + powers the train → drive (forward / back / stop)
     ↑                                                     ↓
Collect coal / wood / scrap / gold  ←  Stop, get out, explore  ←  Obstacle / damage / missing rails
     ↓
Repair (wood + scrap + nails) · Craft at the crafting table · Buy at stations (gold)
```

### Train systems
- **Furnace:** players shovel coal in. Coal gives **speed and heat**. No coal means the train slows and stops.
- **Controls:** forward, reverse, brake/stop (a lever in the cab that anyone can use).
- **Damage:** the train body takes hits and **wheels can fall off**. A damaged train is slower, and a broken one stops.
- **Track problems:** missing rails, broken bridges, missing foundations and rock slides in the mountains.
  Players get off and **rebuild** with wood, scrap and nails.
- **Storage:** a cargo car holds coal, wood, scrap and gold. Eagles can steal from it.
- **Locked container car:** the Chapter 2 surprise (see 3).
- **Crafting table** on the train (see 6).
- **Sacrifice altar** on the train, for reviving (see 8).

### Hands-on repair (RV There Yet style: you do it with your hands, no "hold E")
**Broken track**, step by step:
1. Take **planks** from the cargo car (1 wood each) and carry them in both hands. Place them on the 2 glowing ghost sleepers.
2. **Nail** each plank: 2 nails per plank, **3 hammer hits** per nail (or 1 shot with the **nail gun**). Each nail uses 1 nail.
3. Take **rails** (2 scrap each) and place them on the 2 rail ghosts.
4. **Weld** both ends of each rail with the **welder** (hold LMB). The torch is plugged into a **welder machine by a cable**
   (35 m from the train's machine). Walk too far and the cable stops you; go much further and it unplugs.

**Wheels:** a fallen wheel is gone. Buy a new one at a station, carry it from the cargo car, **lift it into place** (animated),
then **bolt it on with 3 hammer hits**.

**Train body (cover):** at full health every car is fully covered: walls, roofs, doors and the locomotive's boiler plates
(30 breakable pieces in total). Damage makes pieces **break off and fly away**, leaving the bare frame (and gaps you
can fall out of). To fix one: **pick up the fallen piece** (free) or take a **new panel** from the cargo car (2 scrap),
carry it to the ghost, place it, then **nail it** (wood: 2 nails) or **weld it** (metal: 2 welds).
The train's own welder can only weld metal panels while the body is under **60 %**. Above that you need the big
**station welder**, so a badly damaged train has to **limp to the next station**. Doors open and close with E.

Special items found only at stations: **engine oil, repair hammer, nail gun, wheels**.

### Landscape between stations
Stations are **1.5 km apart** (longer in the full game), each stretch with its own theme:
1. Forest hills, with a small river bridge
2. River valley, with a big river bridge
3. Mountain pass: a long climb (uphill = slower and more coal) and a tall trestle over a gorge
4. The lake: downhill to the shore, then a long bridge across the lake
5. The coast: down to the sea and the port

Bridges are wooden trestles. A broken bridge piece leaves a hole you can fall through into the water.

### Resources
| Resource | Where | Used for |
|----------|-------|----------|
| **Coal** | Dropped along the track, coal piles | Furnace: speed and heat |
| **Wood** | Trees, crates, dropped along the track | Track and train repair, crafting, extra furnace fuel (weaker) |
| **Scrap** | Wrecks, dropped items | Repair, crafting |
| **Gold** | Mining **gold rocks** near the track | Shop currency, crafting blueprints. **Carried into Chapter 2** |

### Shops (at stations)
Nail gun · nails · grappling hook (reach cliffs, cross gaps, like Peak) · medkit · train wheels · engine oil · repair hammer ·
blueprint special items (tools, guns)

### Cold and heat
- Areas get cold. The furnace heats the cabin, and players near the heat are safe.
- Out in the cold, players build up **frost**: slower, then taking damage.

## 5. Impostor sabotage
The impostor plays normally (shovels, repairs) but has a **secret sabotage menu** with **cooldowns**.
If the crew votes them correctly, the menu **locks** without telling anyone (see 2).

### Chapter 1 (train)
| Sabotage | Effect | Skill element |
|----------|--------|---------------|
| ☄️ **Meteor** | Impostor picks a spot on the map: on the train, the track ahead, anywhere | The train is moving, so bad timing **misses** |
| 🧟 **Zombie horde** | Zombies attack the train | — |
| 🦅 **Eagles** | Eagles attack and **steal stored resources** (wood, scrap) | — |
| 🌬️ **Freezing wind** | Slows the train, uses more fuel, frost on players unless the furnace burns hot | — |

### Chapter 2 (sea)
| Sabotage | Effect |
|----------|--------|
| 🦈 **Shark** | Attacks the raft and bites pieces off it, or attacks swimmers |
| 🐟 **Piranhas** | A swarm that hurts anyone in the water |
| 🌊 **Tsunami** | A big wave that can flip or damage the raft |
| 🌪️ **Windstorm** | Blows the raft off course or backwards, can knock players into the water |

## 5b. Combat and damage
Players fight zombies, eagles, sharks and the rest with:
| Weapon | How you get it | Notes |
|--------|----------------|-------|
| **Shovel** | Start item (it's also the coal shovel) | Melee, weak, always available |
| **Spear** | Crafting table (wood + scrap) | Melee with longer reach, can be thrown. Good against sharks in Chapter 2 |
| **Guns** | Blueprints (quest reward or bought with gold) + ammo | Strong, ammo is limited |
| **Damaging items** | Shops / crafting (e.g. explosives, traps, molotovs) | Ideas to expand later |

Friendly fire is **on**, which gives the impostor sneaky chances and players plenty of funny accidents.

## 6. Crafting and blueprints
- **Crafting table** on the train (and on the raft in Chapter 2).
- Starting recipe: **spear** (wood + scrap).
- **Blueprints** unlock special items: **tools and guns**. Two ways to get them:
  1. **Earn them** from side quests and puzzles (labyrinth, mountain climb, see 7).
  2. **Buy them with gold** at station shops.

## 7. Quest maps: games inside the game
The side quests are **full separate maps, each like a small game of its own**.
Instead of making one big horror game with many levels, **each quest map takes the feel of one famous game or genre**.
The train stops, the crew enters the quest map, wins a **key** (opens locked routes) and/or a **blueprint**, and gets back to the train.

| Quest map | Inspired by | Gameplay | Reward |
|-----------|-------------|----------|--------|
| **The Mountain** | Peak | A real climbing map. Stamina, grappling hook, helping each other up, falling, cold at the top | Key / blueprint |
| **The Nest** | Backrooms / horror games | A dark labyrinth at night by the zombie nest. Sneak, hide, don't make noise, find the key | Key to a locked route |
| *ideas for more* | | | |
| The Junkyard / Factory | Lethal Company-style scavenging | Grab loot and get out before the monster finds you | Gold + scrap + blueprint |
| The Tower | Only Up / Getting Over It | Vertical parkour, one mistake and you fall | Special blueprint |
| The Mine | Deep Rock-style co-op | Mine gold under a collapsing mine, defend from creatures | Lots of gold |
| The Swamp | Survival horror | Fog, sounds, something hunting you | Key |

- **Make these our own:** same *feel*, but our own art, names and rules. No copying other games' assets or names.
- The impostor can still sabotage inside quest maps *(which sabotages work there is decided per map)*.
- Each quest map is a **separate scene/module**, so we can add them one at a time after the core game works.

## 8. Death and revive
- A dead player leaves a **body**. Teammates must **carry the body** to revive them. Three ways:
  1. **Medkit:** use it on the body.
  2. **Goat sacrifice:** catch a goat (they wander near the track), carry it to the **sacrifice altar on the train**,
     and sacrifice it. That revives a **random** dead player.
  3. **Station grave:** carry the body to the **grave at the next checkpoint station**.
- Dead players spectate until revived.

## 9. Look, camera and UI (reference: RV There Yet)
- **Art style: stylized realism** (updated: assets should be detailed, not childish): realistic proportions with slight
  stylization, detailed hand-painted textures with wear, rust and dirt (Sea of Thieves / Valheim direction).
  Gameplay feel and HUD stay RV There Yet-like.
- **First-person camera** with big cartoony hands visible, holding tools and items.
- **HUD (from the reference screenshots):**
  - Top centre: **train health bar** (green) plus a **journey progress bar** to the next station
  - Top left: carried item counts (e.g. nails, scrap)
  - Bottom left: player status (health, frost, poison)
- **Objective list on paper/phone:** the player holds up a handwritten checklist (like RV There Yet's camping-trip note),
  e.g. "find the train station ✔, reach station 1, get engine oil…". The host can use the **phone with the tracker**.
- Comedy: goofy physics, ragdolls, players carrying each other's bodies around.

## 9b. Game length
- **Chapter 1 ≈ 10 hours when played perfectly** (more for most groups). Chapter 2 adds more on top.
- The length comes mostly from the **quest maps** (each one is a mini game) plus 5 long train runs.
- Saves at every station, so groups play over several sessions.

## 10. Still open
1. **Yacht finale:** when the raft reaches the yacht, what happens: a fight with the kidnapper, a boarding sequence? Who is the kidnapper?
2. **Correct-vote lock:** until the end of the chapter (default), or only for a while?
3. **Which quest maps** go in Chapter 1, and in what order across the 5 runs?

## 11. Technical plan
- **Multiplayer from day one.** It's the hardest part, so the game is built around it.
  Godot high-level multiplayer, **host-authoritative** (the host player's PC runs the game). **Steam lobbies and invites via GodotSteam.**
  Use ENet locally for quick testing.
- **The train is a path follower:** it moves along a track curve (`Path3D` + `PathFollow3D`) with real speed, not full physics.
  It's stable online and easy to derail on purpose at broken track.
- **Players on a moving train or raft:** they stand in the vehicle's local space so they don't slide off. This is a known hard problem, and we solve it early.
- **The raft (Chapter 2)** is a grid-based buildable platform (like Raft) with simple buoyancy and wave motion.
- **Sabotage map:** the impostor opens a top-down map view to place meteors and the rest.
- **Carry system:** pick up and carry bodies, goats and resources. One shared system.
- **Saves:** a checkpoint save at each station (host saves).

### Assets to make (Tripo3D → Blender → Godot, RV There Yet style)
Characters: host, girlfriend, friends (customisable colours and hats), kidnappers, zombies, eagle, goat, shark, piranha, villain.
First-person hands (with holding poses).
Train: locomotive, cargo car, container car, altar/crafting car (modular, damage states, removable wheels).
World: café, store, toilet, train stations ×5 (with shop + grave), track pieces, bridges, mountains, gold rocks, trees, labyrinth, port, yacht, helicopter.
Sea: raft pieces, boat engine, ocean, islands.
Animations: Mixamo / Quaternius (walk, run, shovel, carry, climb, crouch, hit, knocked out, swim, zombie set).

## 12. Build order (milestones)
| # | Milestone | Done when |
|---|-----------|-----------|
| M0 | PC + MCP setup | See `TODO_LOCAL.md` |
| M1 | **Multiplayer base** | 2+ players join a Steam/ENet lobby, walk around in first person and see each other |
| M2 | **Train core** | Train drives on a track, furnace + coal, forward/back/stop, players ride it without sliding |
| M3 | **Gather + repair + carry** | Collect coal/wood/scrap, missing rail repaired, carry items/bodies |
| M4 | **Impostor + voting** | Secret role, sabotage menu + meteor with cooldown, vote that silently locks sabotage |
| M5 | **Vertical slice** ⭐ | Board the train → reach station 1 (shop, station-only repairs, grave), death + medkit revive, cold. **Playtest with friends** |
| M6 | Intro + kidnap | Café intro, 4 kidnap scenes, impostor chooses with a timer |
| M7 | Chapter 1 content | 5 stations, zombies, eagles, freezing wind, wheels, gold rocks, goat altar, crafting + blueprints |
| M8 | Quest maps | The Nest (horror labyrinth) + The Mountain (Peak-style). More maps added one by one later |
| M9 | **Chapter 2** | Container reveal, raft building, sea sabotages, yacht chase + finale |
| M10 | Polish + Steam | Menus, sound, balance, Steam page and export |

The intro comes *after* the train gameplay on purpose. If the train isn't fun with friends, nothing else matters.

## 13. Title ideas (decided: **Trust Issues**)
Other candidates we had, not about the train. About **her**, **the traitor friend** and **the chase**:

| Title | Why |
|-------|-----|
| ⭐ **Who Took Her?** | The impostor literally chose how she was taken. The question stays open all game |
| **Not Without Her** | The boyfriend's promise, and the chase |
| **Among Friends** | One of your friends is the traitor (impostor pun) |
| **Chasing Her** | Simple, it's the whole game |
| **Trust No Friend** | Impostor focus |
| **Date Night Gone Wrong** | Funny, matches the cartoon style |
| **Catch Them If You Can** | The chase |
| **Love & Lies** | Girlfriend + impostor |
