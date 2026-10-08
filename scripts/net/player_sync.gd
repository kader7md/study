class_name PlayerSync
extends RefCounted
## The two MultiplayerSynchronizers every Player gets (see Net._spawn_player):
##
## InputSync  (authority = the player's own peer: client authority for movement only)
##   net_pos, net_yaw, net_pitch, net_car  20 Hz. net_pos is LOCAL to the train car being ridden when net_car >= 0, so
##                                         riders stay glued to the car on every screen (GDD 9: vehicle local space).
##   current_tool, welding                 on change.
## StateSync  (authority = host: game state about the player)
##   carried_item, health, frost, downed, welder_path   on change.
##   Its visibility also gates the MultiplayerSpawner: a client only gets the players once its world is loaded.

const INPUT_PROPS := ["net_pos", "net_yaw", "net_pitch", "net_car"]
const INPUT_ON_CHANGE := ["current_tool", "welding"]
const STATE_PROPS := ["carried_item", "health", "frost", "downed", "welder_path"]
const INTERVAL := 0.05


static func attach(player: Player, peer: int) -> void:
	var input := MultiplayerSynchronizer.new()
	input.name = "InputSync"
	input.replication_config = _config(INPUT_PROPS, INPUT_ON_CHANGE, false)
	input.replication_interval = INTERVAL
	input.delta_interval = INTERVAL
	# The host's own input sync is shown per peer (like StateSync); a client's is public (it can't know who is ready,
	# and packets for players a peer hasn't spawned yet are dropped by Godot).
	input.public_visibility = peer != 1
	player.add_child(input)
	input.set_multiplayer_authority(peer)

	var state := MultiplayerSynchronizer.new()
	state.name = "StateSync"
	state.replication_config = _config([], STATE_PROPS, true)
	state.replication_interval = INTERVAL
	state.delta_interval = INTERVAL
	state.public_visibility = false
	player.add_child(state)
	state.set_multiplayer_authority(1)


## Host: lets `peer` see (and so spawn) this player.
static func show_to(player: Player, peer: int) -> void:
	var state: MultiplayerSynchronizer = player.get_node_or_null("StateSync")
	if state:
		state.set_visibility_for(peer, true)
	var input: MultiplayerSynchronizer = player.get_node_or_null("InputSync")
	if input and player.peer_id == 1:
		input.set_visibility_for(peer, true)


static func _config(always: Array, on_change: Array, spawn: bool) -> SceneReplicationConfig:
	var cfg := SceneReplicationConfig.new()
	for prop: String in always:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, spawn)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for prop: String in on_change:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, spawn)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	return cfg
