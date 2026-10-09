class_name Appearance
extends RefCounted
## How a crew member looks: skin, eyes, eye colour, mouth, accessory (+ its colour) and outfit colour.
## Stored as a short text code (Settings "profile/look", synced as Player.look and in Net.players[id].look):
##   "s2.e:round.c1.m:smile.a:beanie.h3.o0"
## Unknown or broken values fall back to the defaults, so an old or hand-edited code never breaks a character.

const SKINS: Array[Color] = [
	Color("f0c29c"), Color("e8ae84"), Color("d2945f"), Color("c07f52"), Color("8f5a36"), Color("5e3a22"),
	Color("a7d98c"), Color("9cc2f0"), Color("d9b3f0"),
]
const EYES: Array[String] = ["round", "sleepy", "angry", "googly", "dot"]
const EYE_COLORS: Array[Color] = [
	Color("6b3f1f"), Color("2f7fd0"), Color("3f9a4a"), Color("9a7a2e"), Color("6d7680"), Color("8a4fc4"), Color("1c1a1a"),
]
const MOUTHS: Array[String] = ["smile", "grin", "flat", "open", "frown", "teeth"]
const ACCESSORIES: Array[String] = ["none", "beanie", "cap", "hardhat", "glasses", "scarf", "backpack", "mustache"]
## Accessories that cover the hair tuft.
const HATS: Array[String] = ["beanie", "cap", "hardhat"]
const COLORS: Array[Color] = [
	Color("dc6b2e"), Color("2e8f8f"), Color("eebd2e"), Color("8c5cb3"), Color("5c9e45"), Color("c8382a"),
	Color("33528f"), Color("e37fa3"), Color("8a8a8a"), Color("3d3d3d"), Color("f2ead8"),
]
const LABELS := {
	"round": "Round", "sleepy": "Sleepy", "angry": "Grumpy", "googly": "Googly", "dot": "Dot",
	"smile": "Smile", "grin": "Grin", "flat": "Meh", "open": "Oh!", "frown": "Frown", "teeth": "Buck teeth",
	"none": "None", "beanie": "Beanie", "cap": "Cap", "hardhat": "Hard hat", "glasses": "Glasses", "scarf": "Scarf",
	"backpack": "Backpack", "mustache": "Mustache",
}

var skin := 1
var eyes := "round"
var eye_color := 0
var mouth := "smile"
var accessory := "hardhat"
var hat_color := 2
var outfit := 0


func skin_color() -> Color:
	return SKINS[clampi(skin, 0, SKINS.size() - 1)]


func eye_tint() -> Color:
	return EYE_COLORS[clampi(eye_color, 0, EYE_COLORS.size() - 1)]


func hat_tint() -> Color:
	return COLORS[clampi(hat_color, 0, COLORS.size() - 1)]


func outfit_tint() -> Color:
	return COLORS[clampi(outfit, 0, COLORS.size() - 1)]


func duplicate_look() -> Appearance:
	return Appearance.decode(encode())


func equals(other: Appearance) -> bool:
	return other != null and other.encode() == encode()


## The short text code (see the class comment).
func encode() -> String:
	return "s%d.e:%s.c%d.m:%s.a:%s.h%d.o%d" % [skin, eyes, eye_color, mouth, accessory, hat_color, outfit]


## Reads a code; anything missing or wrong keeps its default.
static func decode(code: String) -> Appearance:
	var a := Appearance.new()
	for part in code.strip_edges().split(".", false):
		if part.length() < 2:
			continue
		var key := part.substr(0, 1)
		var value := part.substr(2) if part.substr(1, 1) == ":" else part.substr(1)
		match key:
			"s":
				if value.is_valid_int():
					a.skin = clampi(value.to_int(), 0, SKINS.size() - 1)
			"c":
				if value.is_valid_int():
					a.eye_color = clampi(value.to_int(), 0, EYE_COLORS.size() - 1)
			"h":
				if value.is_valid_int():
					a.hat_color = clampi(value.to_int(), 0, COLORS.size() - 1)
			"o":
				if value.is_valid_int():
					a.outfit = clampi(value.to_int(), 0, COLORS.size() - 1)
			"e":
				if value in EYES:
					a.eyes = value
			"m":
				if value in MOUTHS:
					a.mouth = value
			"a":
				if value in ACCESSORIES:
					a.accessory = value
	return a


## A random look (`rng` for repeatable picks).
static func random(rng: RandomNumberGenerator = null) -> Appearance:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var a := Appearance.new()
	a.skin = rng.randi_range(0, SKINS.size() - 1)
	a.eyes = EYES[rng.randi_range(0, EYES.size() - 1)]
	a.eye_color = rng.randi_range(0, EYE_COLORS.size() - 1)
	a.mouth = MOUTHS[rng.randi_range(0, MOUTHS.size() - 1)]
	a.accessory = ACCESSORIES[rng.randi_range(0, ACCESSORIES.size() - 1)]
	a.hat_color = rng.randi_range(0, COLORS.size() - 1)
	a.outfit = rng.randi_range(0, COLORS.size() - 1)
	return a


## The default look for a player colour (jacket in their lobby colour), used until they pick their own.
static func for_color(color: Color) -> Appearance:
	var a := Appearance.new()
	var best := 0
	for i in COLORS.size():
		if _dist(COLORS[i], color) < _dist(COLORS[best], color):
			best = i
	a.outfit = best
	return a


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- Local player's saved look (Settings, user://settings.cfg [profile] look) ---------------------------------------

## The local player's saved look code ("" = never customised).
static func saved_code() -> String:
	var settings := _settings()
	if settings == null:
		return ""
	return str(settings.call("get_value", "profile", "look", ""))


static func load_local() -> Appearance:
	return Appearance.decode(saved_code())


static func save_local(a: Appearance) -> void:
	var settings := _settings()
	if settings:
		settings.call("set_value", "profile", "look", a.encode())


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"/root/Settings") if tree else null
