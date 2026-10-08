class_name SteamBackend
extends NetBackend
## STUB: the plug-in point for Steam (GodotSteam, https://godotsteam.com). Not active in this build: GodotSteam is a
## GDExtension / custom engine build that is not part of the project yet, so every call returns ERR_UNAVAILABLE.
##
## How the pieces map (full steps in docs/NETWORK.md, "Plugging in Steam"):
##   NetBackend.host(port, max)  -> Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max)
##                                  on "lobby_created"(result, lobby_id): peer = SteamMultiplayerPeer.new();
##                                  peer.create_host(0) (virtual port 0); Steam.setLobbyData(lobby_id, "game", "trust_issues")
##   NetBackend.join(lobby_id)   -> Steam.joinLobby(int(lobby_id)); on "lobby_joined": owner = Steam.getLobbyOwner(lobby_id);
##                                  peer = SteamMultiplayerPeer.new(); peer.create_client(owner, 0)
##   invites                     -> Steam.activateGameOverlayInviteDialog(lobby_id) on the host; a friend accepting it
##                                  fires "join_requested"(lobby_id, friend_id) -> Net.join_game("steam:%d" % lobby_id)
##   describe_invite()           -> {"code": str(lobby_id), "lines": ["Invite friends with Shift+Tab"]}
##   close()                     -> peer.close(); Steam.leaveLobby(lobby_id)
## Peer ids, RPCs, MultiplayerSpawner and MultiplayerSynchronizer work unchanged on SteamMultiplayerPeer, so nothing
## above this file changes. The host's Steam id replaces the IP; NAT punch-through and relays come from Steam.
##
## The calls below go through Engine.get_singleton / ClassDB so this file parses without GodotSteam installed.

var _peer: MultiplayerPeer
var _lobby_id := 0


static func is_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


func backend_name() -> String:
	return "Steam"


func host(_port: int, max_players: int) -> Error:
	if not is_available():
		return ERR_UNAVAILABLE
	var steam := Engine.get_singleton("Steam")
	# Untested sketch of the real flow: the lobby is created asynchronously ("lobby_created"), the peer right away.
	steam.call("createLobby", 1, max_players)  # 1 = LOBBY_TYPE_FRIENDS_ONLY
	_peer = ClassDB.instantiate("SteamMultiplayerPeer")
	return _peer.call("create_host", 0)


func join(address: String, _port: int) -> Error:
	if not is_available() or not address.is_valid_int():
		return ERR_UNAVAILABLE
	var steam := Engine.get_singleton("Steam")
	_lobby_id = address.to_int()
	steam.call("joinLobby", _lobby_id)
	var owner: int = steam.call("getLobbyOwner", _lobby_id)
	_peer = ClassDB.instantiate("SteamMultiplayerPeer")
	return _peer.call("create_client", owner, 0)


func close() -> void:
	if _peer:
		_peer.close()
	if _lobby_id != 0 and is_available():
		Engine.get_singleton("Steam").call("leaveLobby", _lobby_id)
	_peer = null
	_lobby_id = 0


func get_peer() -> MultiplayerPeer:
	return _peer


func describe_invite(_port: int) -> Dictionary:
	return {"code": str(_lobby_id), "lines": PackedStringArray(["Invite friends through the Steam overlay (Shift+Tab)"])}
