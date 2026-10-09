class_name RopeAnchor
extends Interactable
## A piton anchor at the top of a cliff on a quest map ("Anchor_<n>"). [E] with a rope from the crew's coil drops a
## RopeLadder down the cliff: anyone can climb it without using stamina. Host-side (QuestManager.place_rope).

var bottom := Vector3.ZERO     # local to the map: where the ladder ends at the foot of the cliff
var top := Vector3.ZERO
var out := Vector3.ZERO        # outward (away from the cliff)
var exit := Vector3.ZERO       # where you step off at the top
var ladder: RopeLadder


func _ready() -> void:
	add_child(QuestProps.instance("anchor"))
	Build.collider(self, Vector3(1.0, 0.8, 1.0), Vector3(0, 0.3, 0))
	var mark := Build.label(self, "ANCHOR", Vector3(0, 1.1, 0), 32)
	mark.modulate = Color(0.85, 0.9, 1.0)


func get_prompt(_player: Node) -> String:
	if ladder:
		return ""
	var q := Game.quest
	if q == null:
		return ""
	if q.ropes > 0:
		return "Drop a rope ladder down the cliff (%d rope%s)  %s" % [q.ropes, "" if q.ropes == 1 else "s", Settings.key_hint("interact")]
	return "Rope anchor: find a rope coil (camps) to drop a ladder here"


func interact(_player: Node) -> void:
	if Game.quest and ladder == null:
		Game.quest.place_rope(String(name))


## Shows (or removes) the ladder. Called from MountainMap.apply_state on every peer.
func set_placed(on: bool) -> void:
	if on and ladder == null:
		var map := get_parent() as Node3D
		ladder = RopeLadder.new()
		ladder.name = "Ladder_" + String(name)
		map.add_child(ladder)
		ladder.setup(map.to_global(bottom), map.to_global(top), out, map.to_global(exit))
		collision_layer = 0
	elif not on and ladder:
		ladder.queue_free()
		ladder = null
		collision_layer = Build.LAYER_INTERACT
