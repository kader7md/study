class_name HelpSpot
extends Interactable
## The [E] target on another player inside a quest map ("Help", a child of every Player that is not ours):
## a crewmate hanging out of stamina gets PULLED UP next to you; anyone else gets a BOOST (a leg-up onto a ledge).
## Runs on the host (QuestManager.help), which tells the helped player's peer to move.

var target: Player


static func create(p: Player) -> HelpSpot:
	var s := HelpSpot.new()
	s.name = "Help"
	s.target = p
	Build.collider(s, Vector3(1.0, 1.9, 1.0), Vector3(0, 0.95, 0))
	p.add_child(s)
	s.collision_layer = 0
	return s


func _process(_delta: float) -> void:
	# only other players, only inside a quest map, and not while they are down
	var on := Game.in_quest() and not target.is_local() and not target.downed
	collision_layer = Build.LAYER_INTERACT if on else 0


func get_prompt(player: Node) -> String:
	if not Game.in_quest() or player == target:
		return ""
	if target.is_hanging:
		return "Pull %s up  %s" % [target.display_name, Settings.key_hint("interact")]
	return "Give %s a boost  %s" % [target.display_name, Settings.key_hint("interact")]


func interact(player: Node) -> void:
	if player is Player and Game.in_quest():
		Game.quest.help(target, player)
