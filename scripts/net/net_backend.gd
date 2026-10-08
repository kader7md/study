class_name NetBackend
extends RefCounted
## The transport under Net: it only opens and closes a connection and hands Godot a MultiplayerPeer.
## Everything above it (lobby, RPCs, spawning, world sync) is Godot high-level multiplayer and does not care which
## backend made the peer. EnetBackend (UDP, IP + port, invite codes) is the default; SteamBackend is the documented
## plug-in point for GodotSteam (Steam lobbies, friend invites, relay). See docs/NETWORK.md.


## Short id shown in the lobby ("ENet", "Steam").
func backend_name() -> String:
	return "none"


## Starts hosting. max_players counts the host too.
func host(_port: int, _max_players: int) -> Error:
	return ERR_UNAVAILABLE


## Connects to a host. `address` is whatever this backend understands (an IP / host name for ENet, a lobby id for Steam).
func join(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


## Closes the connection (graceful: peers are told at once).
func close() -> void:
	pass


## The peer to put into multiplayer.multiplayer_peer after host() or join() succeeded.
func get_peer() -> MultiplayerPeer:
	return null


## What the host shares with friends: {"code": String, "lines": PackedStringArray of help lines}.
func describe_invite(_port: int) -> Dictionary:
	return {"code": "", "lines": PackedStringArray()}


## Called for each new connection (on the host: every client; on a client: the host, id 1).
func on_peer_connected(_id: int) -> void:
	pass


## True if this backend can try to open the port on the router (UPnP).
func supports_upnp() -> bool:
	return false
