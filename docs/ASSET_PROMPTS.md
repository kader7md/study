# Asset image prompts (Higgsfield → Tripo3D → Blender → Godot)

How to use:
1. Generate each image in **Higgsfield** with the prompt below. Always paste the **STYLE** block first, then the asset line.
2. Pick the best result. **One object per image, plain background, full object visible.**
3. Save it as `assets/concept/<file name>.png` (the names are in the tables) and push it, or send it to Claude.
4. Then: image → **Tripo3D** (image-to-3D, game-ready / low-poly, quad remesh) → `.glb` → Claude cleans it up in Blender
   (scale, origin, splitting into breakable parts) → Godot.

For **train cars**, also generate the **breakable parts** separately (panels, doors, roof, wheels). In the game they fall off one by one.

---

## ⭐ Asset sheets: everything in one image (like the Elden Ring concept sheet)

Generate these in **Higgsfield** in **landscape 16:9 at the highest resolution**. Each sheet is one big image with a
**key art scene on the left** and **rows of labelled assets on the right**, in the same style.
Do the **master sheet** first. If the assets come out too small, use the 5 themed sheets (fewer items each, more detail).
Save them as `assets/concept/sheet_<name>.png`.

### Master sheet (all key assets)
```
Game concept art asset sheet for a cosy cartoon co-op adventure game called "TRUST ISSUES", landscape 16:9 poster layout.
Left third: key art of a chunky red steam train with gold bands crossing a wooden trestle bridge over a turquoise river,
pine forest hills and snowy mountains behind, golden afternoon light, four small chunky cartoon friends on the train.
Right two thirds: neatly organised rows of separate game assets on a dark wooden board, each asset isolated with a small
label underneath, grouped in titled sections:
TRAIN: steam locomotive, covered goods wagon, open workshop wagon with canopy, rusty locked container wagon, spare train
wheel, wooden wall panel, red boiler plate, cab door, roof panel.
TOOLS: claw hammer, orange nail gun, welding torch, portable orange welding machine with cable reel, coal shovel, big wrench.
REPAIR & RESOURCES: wooden railway sleeper plank, steel rail section, box of nails, coal pile, log stack, scrap metal pile,
gold ore rock, wooden crate, medkit, oil can, grappling hook, scrap spear.
NATURE: stylised pine tree, snowy pine, round oak tree, birch tree, spooky dead tree, bush, grass clump, mossy boulder,
layered cliff rock, river stones, low-poly snowy mountain.
STATION & PROPS: small countryside station building, stone platform with roof, market stall shop, wooden water tower,
bench, iron lamp post, blank sign, grave stone, café table and chairs, crafting workbench, round meeting table with a bell,
stone altar with candles, barrel, toolbox, lantern.
Style: stylized 3D game assets, chunky rounded shapes, soft bevelled edges, bright warm colours, clean hand-painted textures,
slightly exaggerated proportions, cosy funny look similar to RV There Yet and Peak, consistent lighting on every asset,
3/4 view, clean presentation, high detail, readable silhouettes
```

### Themed sheets (more detail per asset)
Use the same layout sentence for each, and change only the title and the list:

**Layout sentence (start every themed sheet with this):**
```
Game concept art asset sheet for the cosy cartoon co-op game "TRUST ISSUES", landscape 16:9, small key art scene on the left,
rows of separate isolated assets on the right on a dark wooden board, each with a small label, stylized 3D game assets,
chunky rounded shapes, soft bevels, bright warm colours, hand-painted textures, RV There Yet / Peak style, 3/4 view.
```

1. **`sheet_train`**: key art: the steam train at a small station. Assets: steam locomotive (front 3/4 + side view), same
   locomotive damaged with boiler plates and cab walls missing showing the frame, covered goods wagon and its damaged version,
   open workshop wagon with canopy, rusty locked container wagon with padlock, loose train wheel, wooden wall panel, red boiler
   plate with gold band, cab door with window, roof panel, coupling, buffers, train lamp.
2. **`sheet_tools`**: key art: cartoon hands welding a rail with sparks. Assets: claw hammer, nail gun, welding torch, welding
   machine with cable reel, coal shovel, wrench, crowbar, saw, sleeper plank, steel rail, box of nails, bolts, medkit, oil can,
   grappling hook, scrap spear, lantern, rope coil.
3. **`sheet_nature`**: key art: a railway winding through forest hills to a snowy mountain pass. Assets: 4 pine tree variants,
   snowy pine, oak, birch, willow, dead spooky tree, tree stump, fallen log, 3 bush variants, grass clumps, flowers, ferns,
   small rocks, mossy boulders, cliff rock formations, river stones, snowy mountain, waterfall piece, reeds, lily pads.
4. **`sheet_stations`**: key art: a cosy countryside train station at sunset. Assets: station building, platform with roof,
   ticket booth, market stall shop, water tower, coal bunker, signal post, buffer stop, wooden trestle bridge section,
   track piece, bench, lamp post, blank sign, grave stone, fence pieces, barrels, crates, sacks, harbour dock, villain yacht.
5. **`sheet_characters`**: key art: four chunky cartoon friends arguing on a train roof, one secretly smirking (the impostor).
   Assets (all T-pose, front view): the host in a date outfit, the girlfriend, friend in a hoodie and beanie, friend in overalls
   and cap, henchman in black suit and sunglasses, funny green zombie, angry cartoon eagle, silly goat, black helicopter.

**After the sheets:** send them to me. I'll pick the assets, cut each one out, and write a single-object prompt for each
(the table prompts below) so Tripo3D gets one clean object per image.

---

## Single-asset prompts (for Tripo3D: one object per image)

## STYLE (paste before every prompt)

```
Stylized 3D game asset, chunky rounded cartoon shapes, soft bevelled edges, bright warm colours, simple clean hand-painted
textures, slightly exaggerated proportions, cosy and funny co-op game look (similar mood to RV There Yet, Peak, Fortnite),
soft studio lighting, 3/4 front view from slightly above, single object centred, plain light grey background,
no text, no logo, no shadow on the background, full object visible, game-ready, low-poly friendly
```

For objects you want to turn into 3D, add:
```
, orthographic product shot, clear silhouette, no perspective distortion
```

---

## 1. The train

| File | Prompt (after STYLE) |
|------|----------------------|
| `train_locomotive` | old steam locomotive, deep red boiler with gold bands, black smokebox and tall flared chimney, brass steam dome, green wooden driver cab with round windows and a dark red roof, big red spoked wheels with white rims, cowcatcher at the front, headlamp |
| `train_locomotive_side` | same steam locomotive, perfect side view, showing the boiler, cab, 6 big red wheels and connecting rods |
| `train_locomotive_damaged` | same steam locomotive badly damaged: boiler plates missing showing the iron core underneath, cab walls and one door missing, only the metal frame left, dented, scratched, smoke |
| `train_cargo_wagon` | covered wooden goods wagon on a rail chassis, brown plank walls with iron frame posts, sliding side door, dark red curved roof, small iron steps, crates and coal visible inside the open end |
| `train_cargo_wagon_damaged` | same goods wagon, half of the wall planks and the roof broken off, only the iron frame skeleton left in places |
| `train_utility_wagon` | open flat workshop wagon, green low side boards, cream canvas canopy roof on iron posts, orange welding machine with a cable reel, a wooden crafting table, a small stone altar, a round wooden meeting table |
| `train_container_wagon` | rusty orange corrugated metal container on a rail flatcar, locked back doors with a big gold padlock and chains, mysterious |
| `train_part_wood_panel` | single wooden wall panel of a goods wagon, horizontal planks, two iron bolts, a little worn |
| `train_part_metal_panel` | single curved red metal boiler plate with a gold band and rivets |
| `train_part_door` | single green wooden train cab door with a small window and a brass knob |
| `train_part_roof` | single dark red curved metal train roof panel |
| `train_wheel` | single big red spoked steam locomotive wheel with a white rim and brass hub, front view |

## 2. Repair tools and items (first-person, held in big cartoon hands)

| File | Prompt (after STYLE) |
|------|----------------------|
| `tool_hammer` | chunky claw hammer, wooden handle with a red rubber grip, big steel head |
| `tool_nail_gun` | chunky orange and black cordless nail gun, big trigger, nail magazine |
| `tool_welder_torch` | welding torch / stick welder handle, blue rubber grip, brass nozzle, short black cable |
| `tool_welder_machine` | portable orange arc welding machine on a frame, dials, cable reel with a long black cable, carry handle |
| `tool_shovel` | coal shovel, wooden handle with a D-grip, dented black steel blade |
| `tool_wrench` | huge cartoon adjustable wrench, chrome and red |
| `item_plank` | single wooden railway sleeper / plank, rough sawn wood, a few nails |
| `item_rail` | single short steel railway rail section, I-beam profile, slightly rusty ends |
| `item_nails_box` | small cardboard box overflowing with big shiny nails |
| `item_medkit` | white first-aid case with a red cross, cartoon chunky |
| `item_engine_oil` | old metal oil can with a long spout, yellow and black label shapes (no text) |
| `item_grappling_hook` | grappling hook with three steel claws and a coiled rope |
| `item_spear` | crafted spear, wooden shaft, scrap-metal blade tied with rope |

## 3. Resources along the track

| File | Prompt (after STYLE) |
|------|----------------------|
| `res_coal_pile` | pile of shiny black coal lumps |
| `res_wood_logs` | small stack of chopped wooden logs tied with rope |
| `res_scrap_pile` | pile of scrap metal: bent pipes, gears, rusty plates, bolts |
| `res_gold_rock` | grey boulder with glowing gold ore veins and nuggets |
| `res_crate` | wooden supply crate with iron corners, slightly broken |

## 4. Nature (replaces the simple cones in the prototype)

| File | Prompt (after STYLE) |
|------|----------------------|
| `nature_pine_tree` | stylized pine tree, layered chunky foliage clumps, dark and light green, thick brown trunk |
| `nature_pine_tree_snow` | same stylized pine tree with snow on the branches |
| `nature_oak_tree` | stylized round oak tree, big fluffy foliage clumps, warm green, thick twisted trunk |
| `nature_birch_tree` | stylized birch tree, white trunk with black marks, light yellow-green leaves |
| `nature_dead_tree` | spooky dead tree, twisted bare branches (for the zombie nest) |
| `nature_bush` | round leafy bush with a few small flowers |
| `nature_grass_clump` | clump of tall cartoon grass blades |
| `nature_rock_small` | small rounded grey rock with moss on top |
| `nature_boulder` | big chunky boulder, layered grey stone, moss patches |
| `nature_cliff_rock` | tall layered cliff rock formation, flat stacked stone layers, grey and brown, moss on top |
| `nature_mountain` | stylized low-poly mountain, chunky faceted rock faces, snowy peak, pine trees at the base (backdrop) |
| `nature_river_stones` | group of smooth river stones and pebbles |
| `nature_log_bridge` | fallen tree trunk lying across, mossy |

## 5. Railway and stations

| File | Prompt (after STYLE) |
|------|----------------------|
| `rail_trestle_bridge` | wooden railway trestle bridge section, criss-cross timber supports, rails on top |
| `rail_track_piece` | straight piece of railway track, wooden sleepers and two steel rails, gravel ballast |
| `rail_buffer_stop` | railway buffer stop at the end of a track, red and white |
| `rail_signal` | old railway semaphore signal on a post |
| `station_building` | small countryside train station building, wooden walls, red tiled roof, round clock, benches, lamp posts |
| `station_platform` | stone station platform with a wooden roof on posts |
| `station_shop` | small wooden market stall shop with an awning, crates and tools on display |
| `station_water_tower` | old wooden railway water tower with a spout |
| `station_bench` | wooden station bench with iron legs |
| `station_lamp` | old iron street lamp post with a warm light |
| `station_sign` | blank wooden station name sign on two posts (no text) |
| `station_grave` | small cartoon grave stone with flowers (for reviving dead friends) |
| `port_dock` | wooden harbour dock with ropes and barrels |
| `port_yacht` | huge luxurious white villain yacht, sleek, dark windows |

## 6. Furniture and props (café, train, stations)

| File | Prompt (after STYLE) |
|------|----------------------|
| `furn_cafe_table` | small round café table with two chairs, checkered tablecloth |
| `furn_cafe_counter` | café counter with a coffee machine and cakes |
| `furn_crafting_table` | wooden workbench crafting table with a vice, saw and tools |
| `furn_meeting_table` | round wooden table with a bell on it (for voting meetings) |
| `furn_altar` | small stone sacrifice altar with candles (cartoon, not scary) |
| `furn_barrel` | wooden barrel with iron bands |
| `furn_toolbox` | red metal toolbox, open |
| `furn_lantern` | old oil lantern with a glowing flame |

## 7. Characters and creatures (later, M6+)

| File | Prompt (after STYLE) |
|------|----------------------|
| `char_host` | cartoon young man, chunky round body, big head, casual date outfit (shirt, jacket), worried face, T-pose, full body front view |
| `char_girlfriend` | cartoon young woman, chunky round body, big head, nice date outfit, T-pose, full body front view |
| `char_friend_a` | cartoon chunky guy in a hoodie and beanie, T-pose, full body front view |
| `char_friend_b` | cartoon chunky woman in overalls and a cap, T-pose, full body front view |
| `char_kidnapper` | cartoon henchman in a black suit and sunglasses, chunky, T-pose, full body front view |
| `enemy_zombie` | cartoon zombie, green skin, torn clothes, chunky and funny not gory, T-pose, full body front view |
| `enemy_eagle` | big cartoon eagle with spread wings, brown and white, angry eyebrows, side view |
| `animal_goat` | cartoon goat, white and brown, chunky, silly face, side view |
| `vehicle_helicopter` | black villain helicopter, chunky cartoon shapes |

---

## Tips
- Same STYLE block every time, so all assets match.
- If the colours drift, add: `colour palette: deep red #9E1C14, gold #F2AD2E, forest green #2E6B45, warm brown #8C5428, cream #EDDBAD`.
- Characters for Tripo3D auto-rigging: always **T-pose, front view, arms straight out**.
- Train cars: generate a **side view** too, which helps Tripo3D get the length right.
