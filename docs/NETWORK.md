# Networking (multiplayer)

Trust Issues is 1 to 5 players, **host-authoritative**, on Godot's high-level multiplayer (RPCs,
`MultiplayerSpawner`, `MultiplayerSynchronizer`). The host's PC runs the whole game: train, track, sabotage,
inventory, pickups, damage. Clients move their own player, send requests ("I pressed E on this"), and show the world
the host streams to them. Solo play is the same game with no clients, fully offline.

Code: `scripts/net/` (autoload `Net`), `scenes/net/Lobby.tscn`, tests in `tests/net_test.gd` + `tests/run_net_test.sh`.
Everything in shared gameplay files that exists only for the network is marked `# NET:`.

```
MainMenu ── Host game ──> Net.host_game(port) ──> Lobby (cards, ready, invite code) ── Start ──┐
         └─ Join game ──> Net.join_game(code / ip:port) ──> Lobby ─────────────────────────────┤
                                                                                              v
   every peer: change_scene(Main) ─> builds the same world from Main.SEED ─> client: "world ready"
   host: spawns Players/Player_<id> for everyone, sends the full world state, then streams it (WorldSync)
```

## Backends

`Net` never talks to a transport directly. A **`NetBackend`** (`scripts/net/net_backend.gd`) opens and closes the
connection and hands Godot a `MultiplayerPeer`; RPCs, spawning and syncing do not care which backend made it.

| Method | Meaning |
|--------|---------|
| `backend_name()` | "ENet", "Steam" (shown in the lobby) |
| `host(port, max_players) -> Error` | start hosting (max_players counts the host) |
| `join(address, port) -> Error` | connect (an IP / host name for ENet, a lobby id for Steam) |
| `close()` | leave; peers are told at once |
| `get_peer() -> MultiplayerPeer` | goes into `multiplayer.multiplayer_peer` |
| `describe_invite(port) -> {code, lines}` | what the host shares |
| `on_peer_connected(id)` | per-connection tuning (ENet: timeouts) |
| `supports_upnp()` | ENet only |

**Offline** (the default, and solo): the root peer is Godot's `OfflineMultiplayerPeer`: peer id 1, `is_server()` is
true, so `Net.is_host()` and `Game.is_host()` are true and every request runs locally. `TestTrain` runs this way.
When the host presses Start with nobody else in the lobby, the server is closed and the run is plain offline solo.

### EnetBackend (default)
- UDP, default port **24565** (`Net.DEFAULT_PORT`), up to 5 players (the server allows one extra connection so a 6th
  player can be told "the lobby is full").
- Range-coder compression on both ends.
- Peer timeout 30 to 60 s (`set_timeout(64, 30000, 60000)`): loading the world blocks a peer for a few seconds and
  ENet's default (5 to 30 s) could drop it. Closing the game still disconnects at once (Net closes the peer on
  `NOTIFICATION_WM_CLOSE_REQUEST`); only a crash or a pulled cable takes up to a minute to notice.
- **LAN:** friends on the same network use the LAN address (the lobby lists them, 192.168.x first).
- **Internet:** when hosting, `Net.lookup_public_ip()` finds the network's public IP without opening anything: it asks
  the router (`UPNP.discover()` + `query_external_address()` on a thread) and falls back to an HTTPS lookup
  (`api.ipify.org`); the host can also type it in the lobby's Public IP field. The lobby then shows a second,
  **Internet** code (labelled "needs UDP port N open"). The host forwards **UDP 24565** on the router, or presses
  **"Open the port (UPnP)"** (`add_port_mapping()` on a thread; the mapping is removed when the host leaves).
  Headless runs (tests) skip the lookup (`Net.auto_public_ip`).
- **No network:** the lobby says "no network found, friends can't join" and never offers a 127.0.0.1 code.

### SteamBackend (stub, for later)
`scripts/net/steam_backend.gd` documents the mapping to [GodotSteam](https://godotsteam.com) and returns
`ERR_UNAVAILABLE` until GodotSteam is installed (it calls Steam through `Engine.get_singleton` / `ClassDB`, so the
project parses without it).

**Plugging in Steam**
1. Install GodotSteam (the GDExtension, or the pre-compiled editor with `SteamMultiplayerPeer`). Add `steam_appid.txt`
   (480 for testing) next to the executable, call `Steam.steamInitEx()` early (a small `SteamBoot` autoload before Net).
2. Finish `SteamBackend` (the flow is written out in its header):
   - `host()`: `Steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, max_players)`; on `lobby_created(result, lobby_id)` create a
     `SteamMultiplayerPeer` with `create_host(0)` and set lobby data (game name, protocol version).
   - `join(lobby_id)`: `Steam.joinLobby(lobby_id)`; on `lobby_joined` get `Steam.getLobbyOwner(lobby_id)` and
     `create_client(owner_steam_id, 0)`.
   - `describe_invite()`: the lobby id; the lobby shows an "Invite friends" button calling
     `Steam.activateGameOverlayInviteDialog(lobby_id)`.
   - `close()`: `peer.close()` and `Steam.leaveLobby(lobby_id)`.
3. In `Net.host_game()` / `join_game()`, pick the backend: `SteamBackend` when `SteamBackend.is_available()` and the
   player chose Steam, else `EnetBackend`. Connect `Steam.join_requested(lobby_id, friend_id)` (a friend accepted an
   invite in the overlay) to `Net.join_game("steam:%d" % lobby_id)` and parse that prefix there.
4. Nothing else changes: peer ids, `request()`, the spawner, synchronizers and WorldSync work the same on
   `SteamMultiplayerPeer`, and Steam brings NAT punch-through and relays (no port forwarding).

## Invite codes

An invite code is the host's **IPv4 address and port packed into 6 bytes** (48 bits: `a.b.c.d` then the port, big
endian), written in **Crockford base32** (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`: no I, L, O, U) as 10 characters
in two groups of five (the top 2 of the 50 bits are zero).

| Address | Code |
|---------|------|
| 192.168.1.20:24565 | `60N00-H8QZN` |
| 10.0.0.5:24565 | `0A000-0AQZN` |
| 127.0.0.1:24599 | `3Z000-02R0Q` |

`InviteCode.decode()` (`scripts/net/invite_code.gd`) also accepts a plain `ip`, `ip:port`, `localhost` or a host name,
ignores case, spaces and dashes, and reads O as 0 and I / L as 1. `InviteCode.encode()` / `InviteCode.decode()` (used by `Net.invite_code()` and `Net.join_game()`).
The host has two codes: `Net.lan_code()` (best LAN address, "" without a network) and `Net.internet_code()` (the public
IP: typed, from UPnP or looked up; "" while unknown). `Net.invite_code()` is the internet code when known, else the LAN
code. A client's lobby shows the code it joined with so it can pass it on.

## Lobby

`Net.players` is the host's list, sent to everyone on every change:
`peer id -> {name, ready, color, host, world}` (`world` = that peer has loaded the run's world).

- **Join:** the client connects, then sends `_rpc_register(PROTOCOL, name, rejoin_token)` (the token is "" unless it is rejoining). The host refuses a different `PROTOCOL`
  ("different version"), a run in progress ("already started"), or a 6th player ("the lobby is full"), with the reason
  shown on the client; otherwise it adds the player (unique name, the next free colour) and broadcasts the list.
  A client that gets no answer in 10 s gives up with a hint about the code and the port.
- **Ready:** clients toggle it (`Net.set_ready`), the host is always ready. **Start** is enabled when every client is
  ready (or the host is alone: "Start solo"). The host can **Kick** (reason shown to the kicked player). Names can be
  changed in the lobby (saved to Settings when it exists).
- `Lobby.tscn` opened without a connection (no main menu in the build, or after a disconnect) shows a Play card:
  solo, host on a port, or join by code / IP. It uses `UiTheme` when the menus workstream's theme exists, otherwise a
  fallback with the same palette.

## Starting the run, spawning players

`Net.start_run()` (host): picks the roles, then `_rpc_start_run(seed)` on every peer: `Game.new_game(false)` and
`change_scene_to_file(Main)`. Each peer builds the identical world from `Main.SEED`.

`Main._ready` calls **`Net.spawn_players(main, spawn_xform)`** (`# NET:` hook in main.gd). It creates `Main/Players`
with a **`MultiplayerSpawner`** (custom `spawn_function`, nodes `Player_<peer id>`), and online the `Main/WorldSync`
node. Offline it adds `Player_1` right away and returns it (so `main.player` is set exactly like before). The host
spawns everyone at once (in a line on the departure platform); a client sends "world ready" and gets its own player a
moment later (Net then sets `main.player` and `hud.player`; a "Waiting for the host" card shows meanwhile).

Each Player has two synchronizers (`scripts/net/player_sync.gd`):

| Synchronizer | Authority | Properties |
|--------------|-----------|------------|
| `InputSync` | the player's own peer (movement only) | `net_pos`, `net_yaw`, `net_pitch`, `net_car` at 20 Hz; `current_tool`, `welding` on change |
| `StateSync` | host | `carried_item`, `health`, `warmth`, `bleeding`, `boosted`, `downed`, `welder_path` on change |

- `net_pos` is **relative to the train car** the player stands on (`net_car`), and other screens smooth it in that
  car's space, so riders stay glued to a moving train everywhere (GDD 9: vehicle local space).
- `StateSync`'s visibility also gates the spawner: a client only receives the players once its world is loaded.
  A client's `InputSync` only goes to peers whose `world` flag is set.
- Other players are drawn by **`RemoteBody`** (`scripts/net/remote_body.gd`): a chunky worker in their colour (jacket,
  cap, reflective stripes), a head that follows their look pitch, big hands holding their tool or the plank / rail /
  wheel / panel they carry, a walk cycle and a name tag. Their first-person camera and arms are hidden.

## Host authority and requests

Clients never change game state. `Net.request(target, method, args)`:
- **Offline / host:** calls `target.method(args)` right away and returns the result (identical to the old code).
- **Client:** sends the target's node path, the method, the args (nodes as paths) and the player's **aim point** to the
  host, and returns null.

The host checks every request: the method is in `Net.ALLOWED` for that kind of target (`interact` / `interact_alt` on an
`Interactable`; `tool_hit`, `come_along_hit`, `weld_tick`, `put_back`, `unplug_welder`, `take_damage` only on the
sender's own Player; `buy` on Game; `use` on the SabotageManager **only from the impostor**), every Player argument is
the sender's own, the player is not downed, and the target is within 9 m. Then it runs the call with the sender's
Player and the aim it sent (`Player.net_aim`, used by plank placement).

`player.gd` routes `interact`, `interact_alt`, tool hits (`tool_hit`), the come-along, welding (batched every 0.1 s
into `weld_tick`), `put_back`, the water fall damage and sabotage through `Net.request`. `Game.buy()` routes itself. The
station shop opens on the requesting client's screen (`main.gd` hook + `Net.open_shop_for`).

**Messages:** `Game.say()` on the host sends feedback for a client's request only to that client ("Hands full", "Not
enough wood"); messages from the host player's own input stay on the host (`Net.run_as`); world events (crashes,
sabotage, a wheel came off, someone left) go to everyone. Banners always go to everyone.

## World sync (`scripts/net/world_sync.gd`)

Only changes travel; everything else is identical because the world is built from the same seed. Auto-named nodes are
renamed deterministically on every peer (`WorldSync.name_tree`: `<Class>_<n>` by sibling order) so paths match.
Fixed names: `Repair_<piece>` (+ `Area`, `Plank<k>/Nail<n>`, `Rail<side>`, `Bolt<side>_<n>`, `RailSlot<side>`),
`Pickup_<n>`, `Key_<seg>`, `Gate_<seg>`, `Station<i>`, `Players/Player_<peer>`, cover piece slots `Slot_<part>` and
fasteners `Fix_<part>_<n>`, extras `Zombie_<n>`, `Eagle_<n>`, `Fallen_<n>`, `Anchor_<n>`, `Meteor_<n>`.

| Stream | How | What |
|--------|-----|------|
| Train snapshot | 20 Hz, unreliable ordered (channel 1) | distance, speed, lever, fuel, body / engine / chassis, wheel wear, state and bolt hits, tipped + tip target, current station, come-along hook / anchor, wind, next station, sabotage cooldowns. Clients predict with the speed and glide to it; `Train._physics_process` only places the cars on clients (`# NET:`). |
| Extras | 20 Hz, unreliable, 8 per packet | zombies, eagles, fallen cover pieces, anchor points: what moved plus everything once a second. Clients show frozen puppets; a reliable `_rpc_extras_gone` removes them. |
| Rail pieces | reliable events | broken (index, cratered), repaired (index, roll) |
| Rail repair progress | reliable, polled 8 Hz | `RailRepair.net_state()` per repair: planks (slot, roll, grounded, fixed, nail hits), rails, bolt hits; `apply_net_state()` on clients |
| Cover pieces | reliable, polled 8 Hz | per part: attached, placed (pending), door open, nail / weld progress |
| Team pool (`Game.inventory`) | reliable, on change | the whole dictionary, to everyone |
| Personal inventory (`Game.personal`) | reliable, on change | `_rpc_personal`: each player's own 30 slots, only to that player (the host keeps everyone's; the checkpoint saves them by player name). Clients move slots with `Game.move_slot` (applied at once, then the host's copy wins) |
| Pickups, keys | reliable | taken (path), gold rock hits left |
| Runtime pickups (RunDirector supply / coal crates) | reliable | created (name, item, amount, contents, position) |
| Meteors | reliable | spawn (name, target); clients show the fall, only the host applies the impact (`# NET:` in meteor.gd) |
| Gates, stations, ending | reliable | gate opened (when the gameplay API exists), station reached (+ stats), chapter completed, `run_finished(stats)`, objective text |

A client that finished loading first gets `send_full_state()`: broken pieces with their repair state, rebuilt rolls,
taken pickups, gold rocks, inventory, next station, every cover piece, gates, objective, run stats, runtime crates,
then a snapshot and all extras.

## Roles: the secret impostor

With 3 to 5 players (or `Net.debug_force_impostor = true` for testing) the host picks one player at random at Start.
Each peer receives **only its own role** (`_rpc_role`), sees a private banner after loading, and `Game.role` is set.
Nothing about another player's role is ever sent or printed; the host keeps the impostor's id in memory only to accept
its sabotage requests. With 1 to 2 players there is no impostor and the world sabotages by itself
(`Game.world_sabotage`, GDD 2). Debug F2 (play as impostor) works offline only.

## Disconnects and restarts

- No joining mid-run in v1: a latecomer is turned away with "The run has already started".
- A client leaving: the host removes its player (despawned everywhere) and tells the others.
- The host leaving or closing the game: every client returns to the menu with **"Host left the game"** (a notice card
  that survives the scene change). Kicked or refused players see the reason the same way.
- The crew wiped out, or F5 / F6 on the host: `Net.reload_world()` despawns the players, then every peer reloads Main
  with the host's checkpoint and inventory; the ready / spawn / full-state steps run again.
- Debug keys F2 / F3 / F5 / F6 only work offline or on the host (`# NET:` in game.gd).

## Voice chat (`scripts/net/voice.gd`)

Push-to-talk (`push_to_talk`, V by default; the Settings workstream registers and rebinds it). While held, an
`AudioStreamMicrophone` plays into the muted **Mic** bus, an `AudioEffectCapture` there gives the samples, they are mixed
to 16 kHz mono, squeezed to 8-bit mu-law and sent as 20 ms frames by unreliable RPC (channel 2) to everyone. Each frame
plays on an `AudioStreamGenerator` in a 3D player (bus **Voice**) at the speaker's body, so voices come from where people
stand; the crew list and the speaker's name tag show who talks. It needs `audio/driver/enable_input = true` (set by the
Settings workstream) and a microphone; otherwise it stays off. About 16 KB/s per speaker.

## Tests

```bash
tests/run_net_test.sh                     # GODOT=/path/to/godot if `godot` is not on PATH; about 50 s
```
1. A headless **host** and **client** on 127.0.0.1: join with an invite code, names, ready, start; both load Main; 2
   players, the other one remote with a body and no arms; the train drives (> 20 m on the client); the client picks up
   a pickup, takes a plank, places and nails it on a gap the host broke; the host finishes the repair and the train
   crosses (seen on both, with the client riding along in a wagon); inventory changes; zombie / eagle / meteor puppets,
   knocked-off cover pieces, and the client refitting a panel; the impostor rule with `debug_force_impostor` and a
   sabotage request accepted only from the impostor; a voice frame; a world reload, after which the client takes the
   station welder's torch and welds the chassis; the host leaves and the client is back at the menu with "Host left the
   game".
2. A **latecomer** is turned away mid-run.
3. A **3-player** run without the override: exactly one impostor, no world sabotage.

Each process prints `PASSED` / `FAILED`; the script fails on any failure or script error in the logs.

Screenshots (needs a display; one Godot per command):
```bash
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tests/NetTest.tscn -- shots <dir>
# two windows seeing each other (start the host first):
... res://tests/NetTest.tscn -- host --port 24611 --shot <dir>
... res://tests/NetTest.tscn -- client --port 24611 --shot <dir>
```

## Adding networked gameplay (checklist)

- Change state only where `Game.is_host()` is true; clients must get it from the host.
- A new interaction: make it an `Interactable` (`interact` / `interact_alt` / `on_tool_hit` / `on_weld`); the player's
  existing routing already sends it. A new kind of request needs an entry in `Net.ALLOWED`.
- Name dynamic nodes deterministically if clients will target them (`Thing_<index>`), or let `WorldSync.name_tree` do it
  for things built in the same order everywhere.
- New state clients must see: add it to the snapshot (continuous values) or send an event from `WorldSync` (one-off
  changes). New things that move: add them to the extras.
- Run `tests/run_net_test.sh` before pushing.

## Limits (v1)

- No joining mid-run as a new player; no host migration (the host leaving ends the run).
- **Rejoining:** a player who was in the run may join again while it runs. At the start of the run the host gives each
  client a random per-session rejoin ticket (`_rpc_rejoin_ticket`, 16 random bytes, sent only to that peer; kept in
  `Net._run_roster`). The client keeps it in memory with the address it joined (`Net._rejoin_ticket`, not cleared by
  `leave()`) and sends it with `_rpc_register` when it joins the same address again. Only a matching ticket gets back
  in, under the name it had at the start (the name it sends is ignored), so typing someone's name is not enough. The host
  sends them `_rpc_start_run` with the checkpoint its own world was built from (`_world_cp`) and their role; when their
  world is loaded they get the full state (WorldSync) and a new Player on the train's middle car.
- When a player leaves mid-run the host re-checks the crew wipe (`Game.check_crew_wipe`), and without the impostor
  (or under 3 players) the world sabotages again. Clients may only buy while their player is on the platform of the
  station the train stands at (`Net._near_shop`).
- ENet needs a reachable host (LAN, forwarded port or UPnP); Steam would remove that.
- Fallen pieces and debris are simulated on the host only (clients see frozen puppets that follow it); planks that fall
  into a river and dropped wheels are cosmetic on each peer.
- Prompts on clients read the last state the host sent, so a counter ("Bolt the wheel 2/3") can lag a frame or two.
