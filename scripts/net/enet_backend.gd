class_name EnetBackend
extends NetBackend
## Default backend: ENet over UDP. The host listens on a port (default 24565); friends join with the invite code
## (IPv4 + port, see InviteCode) or by typing the IP. Optional UPnP asks the router to forward the port.

var _peer: ENetMultiplayerPeer
var _upnp: UPNP
var _upnp_port := 0


func backend_name() -> String:
	return "ENet"


func host(port: int, max_players: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	# One spare connection so a 6th player is let in long enough to be told "the lobby is full".
	var err := _peer.create_server(port, max_players)
	if err != OK:
		_peer = null
		return err
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	return OK


func join(address: String, port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	return OK


func close() -> void:
	if _peer:
		_peer.close()
	_peer = null


func get_peer() -> MultiplayerPeer:
	return _peer


func supports_upnp() -> bool:
	return true


func describe_invite(port: int) -> Dictionary:
	var lan := lan_addresses()
	var ip := lan[0] if not lan.is_empty() else "127.0.0.1"
	var lines := PackedStringArray()
	for a in lan:
		lines.append("%s:%d" % [a, port])
	return {"code": InviteCode.encode(ip, port), "ip": ip, "lines": lines}


## The PC's IPv4 addresses on its local networks, best guess first (192.168.x before 10.x and 172.16-31.x).
static func lan_addresses() -> PackedStringArray:
	var found: Array[String] = []
	for a in IP.get_local_addresses():
		if a.is_valid_ip_address() and not a.contains(":") and InviteCode.is_lan(a):
			found.append(a)
	found.sort_custom(func(x: String, y: String): return _rank(x) < _rank(y) or (_rank(x) == _rank(y) and x < y))
	return PackedStringArray(found)


static func _rank(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	return 2


## Blocking (seconds): asks the router to forward `port` (UDP). Run it on a thread.
## Returns {"ok": bool, "external_ip": String, "text": String}.
func open_upnp(port: int) -> Dictionary:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "external_ip": "", "text": "No UPnP router found (forward UDP port %d by hand)" % port}
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"ok": false, "external_ip": "", "text": "The router does not allow UPnP (forward UDP port %d by hand)" % port}
	var map := upnp.add_port_mapping(port, port, "Trust Issues", "UDP", 0)
	if map != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "external_ip": "", "text": "The router refused the port mapping (code %d)" % map}
	_upnp = upnp
	_upnp_port = port
	var external := upnp.query_external_address()
	return {"ok": true, "external_ip": external, "text": "Port %d is open on the router (UPnP)" % port}


## Blocking: removes the UPnP mapping again (if we made one).
func close_upnp() -> void:
	if _upnp and _upnp_port > 0:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = 0


func has_upnp_mapping() -> bool:
	return _upnp != null
