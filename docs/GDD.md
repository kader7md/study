# Game Design Doc (draft v0.1)

**Working title:** *Last Train* (placeholder, other ideas: *Off the Rails*, *Kidnap Express*)
**Engine:** Godot 4 (GDScript) · **Assets:** Tripo3D + Blender (see `VIDEO_METHOD.md`)
**Players:** 1–5 online co-op · **Impostor:** 1 secret saboteur when there are 3–5 players
**Inspired by:** RV There Yet (vehicle co-op chaos), Peak (co-op through hard terrain), Raft (gather, build, repair), Among Us (hidden impostor)

---

## 1. One-line pitch
A man's coffee date goes wrong when his girlfriend is kidnapped. He and his friends chase the kidnapper's helicopter
across the country on an old coal train: gathering fuel, repairing broken rails and fighting zombies, eagles and storms.
**One of the friends is secretly working against them.**

## 2. Roles
| Role | Who | Goal |
|------|-----|------|
| **Host (the boyfriend)** | The player who creates the lobby | Rescue the girlfriend |
| **Friends (crew)** | Invited players | Help the host reach the last station |
| **Impostor** | 1 random crew member (only with 3–5 players) | Plays like a normal crew member, but secretly chooses the kidnap and sabotages the train so the crew fails |

- 1–2 players: no impostor. Pure co-op, and sabotage events happen randomly ("the world" sabotages).
- Only the impostor knows they're the impostor.

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

### Act 3: The Train Chase (main gameplay)
- Ride the train through **5 stations**. Each one is a **checkpoint**, and the game saves on arrival.
- Between stations: keep the train running, gather resources, repair the track, survive sabotage.
- Some routes are **locked** and need a key from a side quest (see 6).

### Finale: The Port
- At the last station the crew finds the **helicopter** parked near a **boat port**.
- The kidnapper's **big yacht** is there. *(Open question: boss fight, chase, rescue sequence? See 9.)*

## 4. Core loop: the train
```
Shovel coal → furnace heats + powers the train → drive (forward / back / stop)
     ↑                                                     ↓
Collect coal / wood / scrap / gold  ←  Stop, get out, explore  ←  Obstacle / damage / missing rails
     ↓
Repair (wood + scrap + nails) · Buy tools at stations (gold)
```

### Train systems
- **Furnace:** players shovel coal in. Coal gives **speed and heat**. No coal means the train slows and stops.
- **Controls:** forward, reverse, brake/stop (a lever in the cab that anyone can use).
- **Damage:** the train body takes hits and **wheels can fall off**. A damaged train is slower, and a broken one stops.
- **Track problems:** missing rails, broken bridges, missing foundations and rock slides in the mountains.
  Players get off and **rebuild** with wood, scrap and nails.
- **Storage:** a cargo car holds coal, wood, scrap and gold. Eagles can steal from it.

### Resources
| Resource | Where | Used for |
|----------|-------|----------|
| **Coal** | Dropped along the track, coal piles | Furnace: speed and heat |
| **Wood** | Trees, crates, dropped along the track | Track and train repair, extra furnace fuel (weaker) |
| **Scrap** | Wrecks, dropped items | Repair, crafting |
| **Gold** | Mining **gold rocks** near the track | Shop currency |

### Shops (at stations)
Nail gun · nails · grappling hook (reach cliffs, cross gaps, like Peak) · medkit · *(more later: lantern, better shovel, weapons?)*

### Cold and heat
- Areas get cold. The furnace heats the cabin, and players near the heat are safe.
- Out in the cold, players build up **frost**: slower, then taking damage.

## 5. Impostor sabotage
The impostor plays normally (shovels, repairs) but has a **secret sabotage menu** with **cooldowns**:

| Sabotage | Effect | Skill element |
|----------|--------|---------------|
| ☄️ **Meteor** | Impostor picks a spot on the map: on the train, the track ahead, anywhere | The train is moving, so bad timing **misses** |
| 🧟 **Zombie horde** | Zombies attack the train | — |
| 🦅 **Eagles** | Eagles attack and **steal stored resources** (wood, scrap) | — |
| 🌬️ **Freezing wind** | Slows the train, uses more fuel, frost on players unless the furnace burns hot | — |
| *(more ideas: jam the brake, spill coal, hide the key)* | | |

- **Impostor wins** if the crew fails: the train is destroyed, everyone is down, or a time limit runs out *(see 9)*.
- **Crew wins** by reaching the port and rescuing her.

## 6. Side quests and puzzles
- **Labyrinth key:** a locked route needs a key. The key is in a **labyrinth near a zombie nest, at night**.
  Players must sneak (stealth: crouch, stay out of zombies' sight) to get it, then unlock the route.
- More puzzle ideas later: switch tracks to the right route, fix a bridge before the train arrives.

## 7. Feel and style
- Co-op chaos and comedy (like RV There Yet and Peak), with tension from the impostor.
- Art style: *open, see 9*. Stylised low-poly is cheaper and fits Tripo3D plus funny physics. Realistic dark fantasy fits the video's look.

## 8. Technical plan
- **Multiplayer from day one.** It's the hardest part, so the game is built around it.
  Godot high-level multiplayer, **host-authoritative** (the host player's PC runs the game).
  Connection: **Steam (GodotSteam)** for invites and lobbies with a friends list, or ENet plus a relay for testing.
- **The train is a path follower:** it moves along a track curve (`Path3D` + `PathFollow3D`) with real speed, not full physics.
  It's stable online and easy to derail on purpose at broken track.
- **Players on a moving train:** they stand in the train's local space so they don't slide off. This is a known hard problem, and we solve it early.
- **Sabotage map:** the impostor opens a top-down map view to place meteors.
- **Saves:** a checkpoint save at each station (host saves).

### Assets to make (Tripo3D → Blender → Godot)
Characters: host, girlfriend, friends (customisable colours), kidnappers, zombies, eagle, villain.
Train: locomotive, cargo car, passenger car (modular, damage states, removable wheels).
World: café, store, toilet, train stations ×5, track pieces, bridges, mountains, gold rocks, trees, labyrinth, port, yacht, helicopter.
Animations: Mixamo / Quaternius (walk, run, shovel, carry, climb, crouch, hit, knocked out, zombie set).

## 9. Open questions (answer these next)
1. **Impostor caught?** Can the crew **vote out** the impostor like Among Us? Does the impostor get revealed at the end?
2. **Losing:** what makes the crew lose? The train destroyed, all players down, a time limit (the helicopter gets too far)?
3. **Finale:** what happens at the yacht? A fight with the kidnapper, a boat chase, a rescue puzzle? Who is the villain?
4. **Combat:** how do players fight zombies: weapons, shovel melee, only defend the train?
5. **Art style:** stylised and cartoony, or realistic and dark?
6. **Platform:** Steam on PC? Do you want Steam friend invites?
7. **Death:** when a player dies, respawn at the train, get revived by friends, or spectate?
8. **Game length:** how long should one full run take (e.g. 1–2 hours)?
9. **Title:** do you like *Last Train*?

## 10. Build order (milestones)
| # | Milestone | Done when |
|---|-----------|-----------|
| M0 | PC + MCP setup | See `TODO_LOCAL.md` |
| M1 | **Multiplayer base** | 2+ players join a lobby, walk around and see each other |
| M2 | **Train core** | Train drives on a track, furnace + coal, forward/back/stop, players ride it without sliding |
| M3 | **Gather + repair** | Collect coal/wood/scrap, missing rail repaired with wood + nails |
| M4 | **Impostor** | Secret role + sabotage menu + meteor with cooldown |
| M5 | **Vertical slice** ⭐ | Board the train → reach station 1 with a shop, 1–2 sabotages, cold. **Playtest with friends** |
| M6 | Intro + kidnap | Café intro, 4 kidnap scenes, impostor chooses with a timer |
| M7 | Content | 5 stations, zombies, eagles, freezing wind, damage and wheels, gold rocks |
| M8 | Labyrinth | Night stealth key quest + locked route |
| M9 | Finale | Port, helicopter, yacht ending |
| M10 | Polish + Steam | Menus, sound, balance, export |

The intro comes *after* the train gameplay on purpose. If the train isn't fun with friends, nothing else matters.
