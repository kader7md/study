class_name QuestMap
extends Node3D
## Base for a quest map (built by QuestManager far from the line, the same on every peer). Positions given to and
## returned by these methods are LOCAL to the map node. Subclasses: MountainMap.

var quest: QuestManager
var title := "Quest"


## Builds everything (deterministic: every peer builds the same nodes with the same names).
func build() -> void:
	pass


func intro_text() -> String:
	return ""


## Global transform where player number `index` (0..4) appears at camp `c`.
func respawn_transform(_c: int, _index: int) -> Transform3D:
	return global_transform


## The camp (checkpoint) a player at local position `p` has reached, or 0.
func camp_at(_p: Vector3) -> int:
	return 0


func camp_name(c: int) -> String:
	return "camp %d" % c


## Shows the quest state (ropes placed, pickups taken, key taken...).
func apply_state(_q: QuestManager) -> void:
	pass


func objective(_q: QuestManager) -> String:
	return ""


## Stamina drain multiplier at local position `p` (chimneys: less).
func drain_factor(_p: Vector3) -> float:
	return 1.0


## How fast the cold rises (+) or falls (-) per second at local position `p` (0..1 scale).
func cold_rate(_p: Vector3) -> float:
	return -0.05


## True on slippery ground (ice) at local position `p`.
func ice_at(_p: Vector3) -> bool:
	return false


## True when a player at local position `p` is lost (in the sea, under the map): back to the last camp.
func is_out(_p: Vector3) -> bool:
	return false
