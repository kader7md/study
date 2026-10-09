class_name SummitKey
extends GateKey
## The gate key waiting at the end of a quest map ("SummitKey"). Taking it wins the quest for the whole crew
## (QuestManager.win: +1 key, then everyone goes back to the portal).


func get_prompt(_player: Node) -> String:
	return "Take the gate key!  %s" % Settings.key_hint("interact")


func interact(_player: Node) -> void:
	if Game.quest and not Game.quest.won:
		Game.quest.win()


func set_taken(on: bool) -> void:
	visible = not on
	collision_layer = 0 if on else Build.LAYER_INTERACT
