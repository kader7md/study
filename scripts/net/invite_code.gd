class_name InviteCode
extends RefCounted
## Invite codes: an IPv4 address and a port packed into 6 bytes (48 bits), written in Crockford base32 as two groups
## of five characters (see docs/NETWORK.md for a worked example). Easy to read out loud: no I, L, O or U, and decoding
## forgives lower case, spaces and the look-alikes (O -> 0, I/L -> 1).
## decode() also accepts a plain address: "192.168.1.20", "192.168.1.20:24565", "localhost" or a host name.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const LENGTH := 10


## "a.b.c.d" + port -> "XXXXX-XXXXX", or "" if the address is not IPv4.
static func encode(ip: String, port: int) -> String:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4 or port <= 0 or port > 65535:
		return ""
	var value := 0
	for p in parts:
		if not p.is_valid_int():
			return ""
		var b := p.to_int()
		if b < 0 or b > 255:
			return ""
		value = (value << 8) | b
	value = (value << 16) | port
	var chars := ""
	for i in LENGTH:
		chars = ALPHABET[value & 31] + chars
		value >>= 5
	return chars.substr(0, 5) + "-" + chars.substr(5)


## Returns {"ok": bool, "ip": String, "port": int, "error": String, "from_code": bool}.
static func decode(text: String, default_port: int) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return _fail("Enter an invite code or an IP address")
	if t.contains(".") or t.contains(":") or t.to_lower() == "localhost":
		return _decode_address(t, default_port)
	var clean := t.to_upper().replace("-", "").replace(" ", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if clean.length() != LENGTH:
		return _fail("An invite code has 10 characters, like ABCDE-12345")
	var value := 0
	for c in clean:
		var v := ALPHABET.find(c)
		if v < 0:
			return _fail("'%s' is not part of an invite code" % c)
		value = (value << 5) | v
	var port := value & 0xFFFF
	if value >> 48 != 0 or port == 0:
		return _fail("That invite code is not valid")
	var ip := "%d.%d.%d.%d" % [(value >> 40) & 255, (value >> 32) & 255, (value >> 24) & 255, (value >> 16) & 255]
	return {"ok": true, "ip": ip, "port": port, "error": "", "from_code": true}


static func _decode_address(t: String, default_port: int) -> Dictionary:
	var host := t
	var port := default_port
	var colon := t.rfind(":")
	if colon != -1:
		host = t.substr(0, colon)
		var p := t.substr(colon + 1).strip_edges()
		if not p.is_valid_int() or p.to_int() <= 0 or p.to_int() > 65535:
			return _fail("'%s' is not a valid port" % p)
		port = p.to_int()
	host = host.strip_edges()
	if host.to_lower() == "localhost":
		host = "127.0.0.1"
	if host.is_empty():
		return _fail("Enter an IP address")
	if host.is_valid_ip_address():
		return {"ok": true, "ip": host, "port": port, "error": "", "from_code": false}
	# Four numbers that are not a valid IP (e.g. 300.1.1.1)
	if host.replace(".", "").is_valid_int():
		return _fail("'%s' is not a valid IP address" % host)
	# A host name (ENet resolves it): letters, digits, dots and dashes only
	if RegEx.create_from_string("^[A-Za-z0-9.-]+$").search(host) == null:
		return _fail("'%s' is not a valid address" % host)
	return {"ok": true, "ip": host, "port": port, "error": "", "from_code": false}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "ip": "", "port": 0, "error": reason, "from_code": false}


## True for addresses that are only reachable inside a home or office network.
static func is_lan(ip: String) -> bool:
	if ip.begins_with("10.") or ip.begins_with("192.168."):
		return true
	if ip.begins_with("172."):
		var second := ip.split(".")[1].to_int()
		return second >= 16 and second <= 31
	return false
