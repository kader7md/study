class_name WheelSlot
extends Interactable
## Where a locomotive wheel goes. Missing: carry a wheel here and place it [E].
## Placed: bolt it on with the hammer (3 hits). Fitted but worn: tighten it with the wrench before it falls off.

var train: Train
var index := 0
var _hits := 0


## NET: bolt hits so far (WorldSync sends them so the "Bolt the wheel 1/3" prompt matches the host).
func net_hits() -> int:
	return _hits


func net_set_hits(n: int) -> void:
	_hits = n


func get_prompt(player: Node) -> String:
	match train.wheel_state(index):
		1:
			if player and player.carried_item == "wheel":
				return "Lift the wheel into place  [E]"
			return "Missing wheel: carry a wheel here (buy at a station, take from the cargo car)"
		2:
			return "Bolt the wheel: hammer [LMB] %d/%d" % [_hits, Train.WHEEL_BOLT_HITS]
	var wear: float = train.wheel_wear[index] / Train.WHEEL_LIMIT * 100.0
	if wear > 0.0:
		return "Wheel worn %d%%: tighten it with the wrench [LMB] before it falls off" % int(wear)
	return "Wheel OK"


func interact(player: Node) -> void:
	if player and train.wheel_state(index) == 1 and player.carried_item == "wheel":
		player.consume_carried()
		_hits = 0
		train.place_wheel(index)


func on_tool_hit(tool: String, _player: Node) -> bool:
	if tool == "wrench" and train.wheel_state(index) == 0:
		return train.tighten_wheel(index)
	if train.wheel_state(index) != 2 or not tool in ["hammer", "nail_gun"]:
		return false
	_hits += 1
	if _hits >= Train.WHEEL_BOLT_HITS:
		train.bolt_wheel(index)
	return true
