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
- Some routes are **locked** and need a key from a side quest (see 7). **v1 placeholder:** every segment has one locked
  gate and its key lies right beside it (see "Locked gates" in 4) until the quest maps exist.
- **Ending:** when the train stops at station 5 (the port), sabotage stops and a **"Chapter 1 complete"** card shows the
  run stats (time from leaving the departure station, distance, track pieces rebuilt, panels refitted, wheels lost,
  gates opened, gold found) with *Back to main menu* or *Keep exploring*.
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
- **Stopping at a station:** a station counts when the train stops with its middle on the platform. Roll past and the
  objective says so ("You passed station N: pull the lever back"), and the journey strip shows the metres behind you.
  A station further on also counts if the train stops there. The line ends in a buffer stop just after the last
  platform, so the final stop always counts.
- **Furnace:** players shovel coal in. Coal gives **speed and heat**. No coal means the train slows and stops.
- **Controls:** forward, reverse, brake/stop (a lever in the cab that anyone can use).
- **Damage:** the train body takes hits and **wheels can fall off**. A damaged train is slower, and a broken one stops.
- **Track problems:** missing rails, broken bridges, missing foundations and rock slides in the mountains.
  Players get off and **rebuild** with wood, scrap and nails.
- **Storage:** a cargo car holds coal, wood, scrap and gold. Eagles can steal from it.
- **Locked container car:** the Chapter 2 surprise (see 3).
- **Crafting table** on the train (see 6).
- **Sacrifice altar** on the train, for reviving (see 8).

### Locked gates (one per segment, placeholder for the quest maps)
- In the second half of every segment a **heavy striped timber boom** is padlocked across the rails, always on solid
  ground (never on a bridge or by water, never within 30 m of a gap or a station). A **red signal post** stands 120 m before it.
- The train stops in front of it: gently below crash speed, or with **half the crash damage** if it comes in too fast.
- Its **key** lies **4-10 m beside the track, within 8 m of the gate**: a big glowing iron key that bobs and spins, with a
  warm light, a beam of light and a KEY label, so it is found within seconds. [E] picks it up; [E] on the padlock uses it:
  the padlock drops, the boom swings up, the lamps turn green, and the train can go on.
- Gates behind the last checkpoint stay open (their keys are gone). Later, each key comes from a quest map (see 7) instead.

### Hands-on repair (RV There Yet style: you do it with your hands, no "hold E")
**Broken track: free building, together** (anywhere on the line)
1. Carry **planks** from the cargo car and place them where you aim (they snap to the 4 sleeper positions of the gap).
   A see-through preview shows the result: 🟩 rests on the ground, 🟨 needs joining (over water), 🟥 will fall.
   - **On the ground** a plank rests on the ground, so **bumpy ground tilts it** (meteor craters are very bumpy).
     Nail it down with the hammer (2 nails), then **tap it with the hammer to level it**.
   - **Over a river** there is no ground. A plank needs a **supported neighbour** (another plank or the intact track)
     and must be **joined to it with the NAIL GUN**, so the crew builds a platform out over the water.
     A plank with nothing under it and no neighbour **falls into the water** (the wood is lost).
2. Carry **rails** onto the planks (a rail needs at least 3 of the 4 planks under it).
3. **Bolt the fishplates** at both ends of each rail (hammer / nail gun). The bolts come with the rail (no nails).

**Build quality matters:** the rebuilt piece keeps the average tilt of its planks (plus sag for missing ones).
- tilt **4-8°**: bumpy, the wheels shake loose (wheel wear)
- tilt **over 8°**: the train **tips over sideways** (damage, can't move)

**Tipped train → come-along (hand winch).** Hook the come-along to the locomotive's **lifting eye**, chain it to a
**tree or rock on the high side** (anchor points appear), then **crank** it (LMB, one notch per click; several players can
crank together) until the train is back on the rails.

**Welding only exists at stations.** Every station has a welder machine. Take its **welding torch** [E]; the torch is on
a **cable** (30 m): walk too far and it stops you, go much further and it pulls out.

**Wheels:** a fallen wheel is gone. Buy a new one at a station, carry it from the cargo car, **lift it into place** (animated),
then **bolt it on with 3 hammer hits**. With fewer than 3 wheels (or a wrecked train) the train only **limps** at walking
pace, so it can always reach a station.

### Train damage: two bars (100 % = 50 % body + 50 % mechanics)
HUD top centre: 🟩 **body bar** (shield), then one striped **mechanics bar** in three segments: **6 yellow wheel cells**
(a cell empties as its wheel wears loose; a lost wheel is an empty cell with an x), 🟥 **engine** and 🟦 **chassis**, with
their icons underneath and a skull at the end while the train is critical.
Every hit is split **half to the body, half to the mechanics** (two random wheels wear, the chassis bends, the engine suffers).

| Part | Share | What damage does | How to fix |
|------|-------|------------------|------------|
| **Body / cover** | 50 % | Panels, roofs, doors, boiler plates **break off and fly away** (bare frame, gaps you can fall out of) | Pick up the piece or take a new panel (2 of your own scrap), place it: **wood → nails** (anywhere), **metal → weld** (station) |
| **Wheels** (6) | 15 % (2.5 % each) | Each wheel has its own wear. At **2.5 % (5 % of the mechanics bar)** it **comes off and drops to the ground**; each lost wheel = **-1/6 speed** (with N wheels: -1/N) | **Wrench**: tighten a loose wheel before it falls. Lost: buy a new wheel, lift it in, bolt with the hammer |
| **Engine** | 20 % | Less power (up to -50 % speed). Big damage when the engine **goes into water** (crash at a broken bridge) | **Engine oil** at the furnace [Q] (shop) |
| **Chassis** | 15 % | Only a value (it never falls off), makes the train drag (up to -30 % speed) | **Welder at a station**: glowing weld points on the frame |

**Doors** open with E. The locomotive cab has **two front doors** (one each side of the boiler) that swing forward: open them
to see where you're going and walk out along the wide running boards to the front of the engine.

### The train (reference: GWR 7822 "Foxcote Manor" photos)
Realistic steam engine look: black smokebox with a numberplate, green boiler and cab with orange-black lining,
brass safety-valve bonnet, copper-capped chimney, red riveted buffer beam with big buffers, coal bunker at the back of the cab.
Brown goods van with a grey roof, an open workshop wagon, and the rusty locked container.

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
Nail gun · nails · planks (wood) · rails · bolts · scrap · coal · food (sandwich, hot soup, canned beans, coffee) · grappling hook (reach cliffs, cross gaps, like Peak) · medkit · train wheels ·
engine oil · come-along · later: repair hammer and blueprint special items (tools, guns)

### Balance (Chapter 1, v1; constants in `game.gd`, `track.gd`, `main.gd`, `train.gd`, `sabotage_manager.gd`)
One broken piece on solid ground costs about **4 wood** (planks), **2 rails**, **8 nails** (2 per plank) and **4 bolts**
(one per fishplate bolt), all from the **shared team pool**.

**Inventories.** The crew shares one **team pool**: planks (wood), rails, nails, bolts, engine oil, spare wheels and gold.
Everyone builds with it, pickups of those go into it (they carry a small TEAM sign), and the HUD shows it top centre.
Everything else is **personal**: each player has a 5-slot hotbar (keys 1-5) and a 5x5 grid ([Tab]) for tools (hammer,
wrench, nail gun, come-along), coal, scrap, food, medkits, gate keys and gold nuggets. Gold rocks give nuggets that sell
at a station shop (1 gold each) for the crew. Host-authoritative; each client only knows its own inventory.

| What | Value | Why |
|------|-------|-----|
| Start: team pool | 10 wood, 5 rails, 30 nails, 12 bolts, 15 gold, 1 spare wheel, 1 engine oil | Covers a couple of meteor holes or panels on top of the gaps |
| Start: each player | hammer, wrench, a sandwich, 10 coal, 4 scrap, 2 apples (the host also brings the come-along) | |
| Pre-placed gaps | segment 1: **2**, segments 2-5: **3**, 1-2 pieces each, one per third of the segment | Never on a bridge (that needs the nail gun), never within 60 m before a gate |
| Supplies beside every gap (within 22 m) | 2-3 wood piles (4 wood per piece + 1), rails (2 per piece), a nail crate (8 per piece), a bolt crate (4 per piece), 3-4 coal; a gold rock at every other gap | A crew that never shops still has enough |
| Beside every gate | 4 coal and a gold rock | The crew stops there anyway |
| Along the line | a pile every ~34 m (60 % coal, 20 % wood, 20 % scrap), 3 extra gold rocks per segment 6-14 m out; food every ~120 m (apples, beans, chocolate, a sandwich, coffee) | Coal near the track is 4-8x the burn; the coal at the gaps and gate alone is ~1.5-2.5x (checked by TestRoute) |
| Gold rock | 3 hits x 2 nuggets (sold 1 gold each) | Each segment has 30+ gold near the track: a wheel + oil (14) and more |
| Shop | nails x10 = 4, wood x5 = 3, rails x2 = 3, bolts x8 = 3, coal x5 = 2, scrap x5 = 3, wheel = 8, oil = 6, medkit = 7, come-along = 10, nail gun = 15, sandwich = 4, hot soup = 3, beans x2 = 4, coffee = 2 (grappling hook = 12 once the climbing maps exist) | Wood, rails and bolts are the softlock fallback |
| Food | sandwich +35, beans +22, chocolate +14, apple +10, hot soup +15 and +60 warmth, coffee +4, +25 warmth and faster walking for 20 s, medkit +50 (stops bleeding) | Health only comes back by eating (or a revive) |
| Crash | (speed - 4 m/s) x 3.5 + 4 damage (a locked gate: half) | Full speed into a gap ≈ 39 of 100 |
| Wheels | wear at 2.5 falls off; bumpy track (4-8° tilt) +0.4 per crossing; crash damage spreads over 2 wheels | Tighten with the wrench in time |
| World sabotage (1-2 players) | every 100-160 s in segment 1, 80-140, 65-120, 55-105, 50-95 s by segment 5; never within 20 s of leaving a station; world meteors avoid bridges and gates | Calm start, busier towards the port |
| Softlock guards | supply crate (6 wood, 10 nails, 2 rails, 4 bolts; + a loaned nail gun over water) when stopped at a gap without the materials or the gold to buy them; a coal crate when out of coal and gold; one emergency wheel per station when under 3 wheels and broke; a limping train can always reverse or crawl to a station | |
| Pace | ~2.5 min of driving per segment; with 3-5 pieces to rebuild by hand, the gate and the stops: about 6-10 min per segment solo | |

### Cold and heat
- Areas get cold. The furnace heats the cabin, and players near the heat are safe.
- Out in the cold (the freezing wind, or a map's cold zone: `Player.cold_zone`) a player's **warmth** drains: below
  half they are slower, at 0 they take damage. The furnace and a station's shelter warm them back up; hot soup and
  coffee too. Hard hits make a player **bleed** for a few seconds. Health does not come back by itself: **eat**.
  Status icons over the health bar: chilly / cold / freezing, bleeding, warming up, coffee kick, heavy load.

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
**Until the quest maps exist**, each segment's key simply lies beside its locked gate (see "Locked gates" in 4).

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
- *Prototype stopgap until M5:* a downed player is revived by a crewmate's medkit (aim + E), a medkit in your own
  inventory saves you once when you would go down, and everyone who is down gets up when the train reaches the
  next station. Health only comes back by eating.

## 9. Look, camera and UI (reference: RV There Yet)
- **Art style: stylized realism** (updated: assets should be detailed, not childish): realistic proportions with slight
  stylization, detailed hand-painted textures with wear, rust and dirt (Sea of Thieves / Valheim direction).
  Gameplay feel and HUD stay RV There Yet-like.
- **First-person camera** with big cartoony hands visible, holding tools and items.
- **Crew members (our own design, cartoon, RV There Yet spirit):** the people are the one deliberately cartoony part:
  a chunky body, a big round head, stubby limbs, flat colours with soft shading (`build_character.py`, rigged, every
  animation keyframed in Blender). Everyone picks a look: skin colour, eyes (round, sleepy, grumpy, googly, dot), eye
  colour, mouth (smile, grin, meh, oh!, frown, buck teeth), one accessory (beanie, cap, hard hat, glasses, scarf,
  backpack, mustache, none) and its colour, outfit colour, or Randomise. Edited at the **mirror** in the utility wagon
  (a real reflection; [E] opens the editor with a live 3D preview) or from the main menu. Saved per player, synced online.
- **Animation:** other players are fully animated (`CharacterAnimator`, an AnimationTree driven by their state):
  idle / walk / run / jump / fall / crouch / downed / climb for the body; carrying (plank on the shoulder, rail, wheel,
  panel in front), holding a tool and welding layered on the upper body; one-shot actions per tool (hammer swing,
  wrench turn, nail gun recoil, come-along pump) and for shovelling coal, the lever, reaching and waving ([B]).
  Your own first-person hands show your skin colour and sleeves.
- **UI look (our own design, same cosy and chunky spirit as the reference, nothing copied):** one warm theme
  (`UiTheme`, built in code) for every menu, HUD card and panel: cream paper and varnished wood panels, dark ink
  outlines, big rounded corners, soft drop shadows, bold Open Sans text, rust and teal accents, honey hover states.
  Train colours: body green, wheels yellow, engine red, chassis blue, journey orange.
- **HUD** (`scripts/ui/hud.gd` + `scripts/ui/hud/`, look in `HudStyle`): minimal and clean like the reference, our own
  drawing: white rounded outlines, soft drop shadows, diagonal-striped bar fills, small white line icons drawn in code,
  the rounded **Fredoka** font (SIL OFL), no heavy panels over the view.
  - Top centre: **train status** only: body bar (green, shield) and the striped mechanics bar (wheels with one cell per
    wheel, engine, chassis, icons under them, a skull when critical). Above them, only while the come-along is in play,
    a **winch line** (hook — train — anchor, red padlocks where it is not attached, chevrons while pulling)
  - Left of the train bars: the **shared team supplies** as white icon + number (planks, rails, nails, bolts, oil, spare
    wheels, gold); top-left corner: multiplayer widgets (crew list, speaking marks)
  - Top right: speed, lever, fuel, the freezing-wind warning, and small toasts under them
  - Centre: a small crosshair dot (a ring fills while holding [E]), the interaction prompt with key caps; banners and the
    objective show briefly when they change (the journey strip and the help panel are gone: help is in the pause menu
    and while [H] is held)
  - Bottom left: status effect icons, the striped **health** bar, a stamina bar (hidden; `HUD.set_stamina(value, visible)`
    for maps that need it) and the **warmth** bar
  - Bottom centre: the personal **hotbar** (slots 1-5; the station torch shows as an extra slot while held)
  - Right: **context key hints** for what is in hand (e.g. "LMB Pull · R Release"), from the current bindings
  - [Tab]: the **inventory** window (5x5 grid + hotbar row, drag & drop, tooltips, the team supplies beside it);
    the station shop and the pause menu use the same dark-glass style
  - Readable at 1280x720 and 1920x1080 (the UI scales with the window height)
- **Menus:** the title screen shows **TRUST ISSUES** over a slow camera at the departure station (the real Chapter 1
  world from the same seed, chimney smoke, a small generated music-box loop). Buttons: **Continue (station N)** (only
  with a solo save), **Play solo**, **Host game**, **Join game** (invite code or IP:port; you join with the name in the
  name card at the bottom right), **Settings**, **Quit**. Play solo over an existing save asks first. **Esc** in game opens
  the pause menu (Resume, Restart from the last station (solo / host), Settings, Back to menu, Quit). Solo play pauses;
  online the game keeps running. Actions that end the run for the whole crew (the host's Back to menu or Quit) ask
  first. Solo and hosted runs keep separate saves (`checkpoint_solo.json`, `checkpoint_host.json`).
- **Invites:** the host's lobby shows two codes: **Same Wi-Fi** (the LAN address) and **Internet** (the public address,
  found by asking the router or an HTTPS lookup, or typed by the host; it needs UDP port 24565 forwarded, by hand or
  with UPnP). With no network it says so and shows no code. Steam invites (no port forwarding) come with the Steam
  backend. A player who drops out can rejoin the running run with the same name.
- **Settings** (saved in `user://settings.cfg`, applied at startup): **Controls** (rebind every action, keyboard or mouse,
  conflict warnings, reset to defaults, mouse sensitivity, invert Y), **Graphics** (window mode: Windowed, Borderless
fullscreen or Fullscreen; V-Sync, resolution scale,
  shadow quality, anti-aliasing, FOV, max FPS), **Audio** (Master, Music, SFX, Voice), **Microphone** (input device, live
  level meter, "hear yourself" test, push-to-talk on/off and key (with push-to-talk off, an open mic with a noise gate),
your name).
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
  *Built (v1, see `docs/NETWORK.md`):* ENet behind a backend layer that GodotSteam plugs into; host on a port, join by
  invite code (IP + port in 10 characters) or IP; a lobby with names, colours, ready and kick; the host starts the run
  and every peer builds the same world from the seed. Clients move themselves and ask the host for everything else
  (use, tool hits, carry, weld, buy, sabotage). The host streams the train 20 times a second plus every repair, pickup,
  inventory change and sabotage. Exactly one secret impostor with 3 to 5 players, told only to that player.
  Proximity voice chat (push-to-talk or open mic with a noise gate). A player who drops out can rejoin the running run with
  the same name; brand-new players cannot join mid-run yet. If the host leaves, the run ends for everyone.
- **The train is a path follower:** it moves along a track curve (`Path3D` + `PathFollow3D`) with real speed, not full physics.
  It's stable online and easy to derail on purpose at broken track.
- **Players on a moving train or raft:** they stand in the vehicle's local space so they don't slide off. This is a known hard problem, and we solve it early.
  *Built:* online, each player's position is sent relative to the car they stand on, so riders stay glued to the train on every screen.
- **The raft (Chapter 2)** is a grid-based buildable platform (like Raft) with simple buoyancy and wave motion.
- **Sabotage map:** the impostor opens a top-down map view to place meteors and the rest.
- **Carry system:** pick up and carry bodies, goats and resources. One shared system.
- **Saves:** a checkpoint save at each station (host saves). *Built:* `checkpoint_solo.json` / `checkpoint_host.json` with inventory, train, stats and opened gates.

### Assets to make (Tripo3D → Blender → Godot, RV There Yet style)
Characters: host, girlfriend, friends (customisable colours and hats), kidnappers, zombies, eagle, goat, shark, piranha, villain.
First-person hands (with holding poses).
Train: locomotive, cargo car, container car, altar/crafting car (modular, damage states, removable wheels).
World: café, store, toilet, train stations ×5 (with shop + grave), track pieces, bridges, mountains, gold rocks, trees, labyrinth, port, yacht, helicopter.
Sea: raft pieces, boat engine, ocean, islands.
Animations: Mixamo / Quaternius (walk, run, shovel, carry, climb, crouch, hit, knocked out, swim, zombie set).

## 12. Build order (milestones)
| # | Milestone | Done when | Status (polish v1, `743ce70`) |
|---|-----------|-----------|--------|
| M0 | PC + MCP setup | See `TODO_LOCAL.md` | open (needs the local PC) |
| M1 | **Multiplayer base** | 2+ players join a Steam/ENet lobby, walk around in first person and see each other | ENet done (lobby, invite codes, rejoin, net test); Steam backend stubbed |
| M2 | **Train core** | Train drives on a track, furnace + coal, forward/back/stop, players ride it without sliding | done |
| M3 | **Gather + repair + carry** | Collect coal/wood/scrap, missing rail repaired, carry items/bodies | done except carrying bodies |
| M4 | **Impostor + voting** | Secret role, sabotage menu + meteor with cooldown, vote that silently locks sabotage | role and sabotage done; voting open |
| M5 | **Vertical slice** ⭐ | Board the train → reach station 1 (shop, station-only repairs, grave), death + medkit revive, cold. **Playtest with friends** | built (down + medkit revive); grave and the friends playtest open |
| M6 | Intro + kidnap | Café intro, 4 kidnap scenes, impostor chooses with a timer | open |
| M7 | Chapter 1 content | 5 stations, zombies, eagles, freezing wind, wheels, gold rocks, goat altar, crafting + blueprints | 5 stations, locked gates + keys, sabotage, wheels, ending card done; gold rocks, altar, crafting open |
| M8 | Quest maps | The Nest (horror labyrinth) + The Mountain (Peak-style). More maps added one by one later | open (keys lie beside the gates until then) |
| M9 | **Chapter 2** | Container reveal, raft building, sea sabotages, yacht chase + finale | open |
| M10 | Polish + Steam | Menus, sound, balance, Steam page and export | menus, settings, theme, HUD, balance v1 done (see `POLISH_REPORT.md`); sound, Steam, export open |

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
