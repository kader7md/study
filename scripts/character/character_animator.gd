class_name CharacterAnimator
extends AnimationTree
## Plays the crew member's Blender animations (assets/models/character/character.glb) from the player's state.
##
## Tree (built in code):
##   move     Transition idle / walk / run / crouch, time-scaled by the walking speed
##   base     Transition move / jump / fall / downed / climb                    (full body)
##   hold_r   Blend2 base + hold_tool, filtered to the right arm               (holding a tool, left arm still swings)
##   hold     Blend2 hold_r + carry_shoulder / carry_front / weld, upper body  (carrying, welding)
##   act      OneShot hold + one tool action, upper body                       (hammer, wrench, nail_gun, crank, shovel,
##                                                                              lever, interact, wave)
## Which clip plays is decided by the static base_clip() / hold_clip() / action_clip() (tested in TestCharacter).

## Player state the animations follow (set by CharacterModel / RemoteBody every frame).
class State:
	var speed := 0.0          ## horizontal speed, m/s
	var on_floor := true
	var vertical := 0.0       ## vertical speed, m/s (> 0 = going up)
	var carried := ""         ## plank / rail / wheel / panel / ""
	var tool := ""            ## hammer / wrench / nail_gun / welder / come_along / ""
	var welding := false
	var downed := false
	var climbing := false
	var crouching := false

const LOOPED: Array[String] = ["idle", "walk", "run", "crouch", "fall", "downed", "climb", "hold_tool",
	"carry_shoulder", "carry_front", "weld"]
const MOVE_CLIPS: Array[String] = ["idle", "walk", "run", "crouch"]
const BASE_INPUTS: Array[String] = ["move", "jump", "fall", "downed", "climb"]
const HOLD_CLIPS: Array[String] = ["carry_shoulder", "carry_front", "weld"]
const ACTIONS: Array[String] = ["hammer", "wrench", "nail_gun", "crank", "shovel", "lever", "interact", "wave"]
## Tool -> its one-shot action clip (the welder is continuous: the "weld" hold instead).
const TOOL_ACTIONS := {"hammer": "hammer", "wrench": "wrench", "nail_gun": "nail_gun", "come_along": "crank"}
const TOOLS_HELD: Array[String] = ["hammer", "wrench", "nail_gun", "welder", "come_along"]
const WALK_SPEED := 3.2   ## the speed the walk clip was keyed for (its playback scales with the real speed)
const RUN_SPEED := 7.0
const RUN_ABOVE := 5.6

const RIGHT_ARM: Array[String] = ["shoulder.R", "upper_arm.R", "forearm.R", "hand.R"]
const UPPER_BODY: Array[String] = ["spine", "chest", "neck", "head", "shoulder.R", "upper_arm.R", "forearm.R", "hand.R",
	"shoulder.L", "upper_arm.L", "forearm.L", "hand.L"]

var state := State.new()
var current_base := "idle"
var current_hold := ""
var last_action := ""
var _skeleton_path := ""


## `player`: the glb's AnimationPlayer (its library is shared, not copied). Add the tree as a sibling of it.
func setup(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var lib := player.get_animation_library("")
	for clip: String in LOOPED:
		if lib.has_animation(clip):
			lib.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	add_animation_library("", lib)
	root_node = NodePath("..")
	_skeleton_path = str(player.get_parent().get_path_to(skeleton))
	tree_root = _build_tree()
	active = true
	set("parameters/move/transition_request", "idle")
	set("parameters/base/transition_request", "move")


func _build_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var move := AnimationNodeTransition.new()
	move.xfade_time = 0.18
	for i in MOVE_CLIPS.size():
		move.add_input(MOVE_CLIPS[i])
		bt.add_node("a_" + MOVE_CLIPS[i], _anim(MOVE_CLIPS[i]))
	bt.add_node("move", move)
	for i in MOVE_CLIPS.size():
		bt.connect_node("move", i, "a_" + MOVE_CLIPS[i])
	bt.add_node("move_speed", AnimationNodeTimeScale.new())
	bt.connect_node("move_speed", 0, "move")

	var base := AnimationNodeTransition.new()
	base.xfade_time = 0.16
	for i in BASE_INPUTS.size():
		base.add_input(BASE_INPUTS[i])
	base.set_input_reset(1, true)  # jump plays from the start every time
	bt.add_node("base", base)
	bt.connect_node("base", 0, "move_speed")
	for i in range(1, BASE_INPUTS.size()):
		bt.add_node("a_" + BASE_INPUTS[i], _anim(BASE_INPUTS[i]))
		bt.connect_node("base", i, "a_" + BASE_INPUTS[i])

	bt.add_node("a_hold_tool", _anim("hold_tool"))
	var hold_r := AnimationNodeBlend2.new()
	_filter(hold_r, RIGHT_ARM)
	bt.add_node("hold_r", hold_r)
	bt.connect_node("hold_r", 0, "base")
	bt.connect_node("hold_r", 1, "a_hold_tool")

	var hold_sel := AnimationNodeTransition.new()
	hold_sel.xfade_time = 0.15
	for i in HOLD_CLIPS.size():
		hold_sel.add_input(HOLD_CLIPS[i])
		bt.add_node("a_" + HOLD_CLIPS[i], _anim(HOLD_CLIPS[i]))
	bt.add_node("hold_sel", hold_sel)
	for i in HOLD_CLIPS.size():
		bt.connect_node("hold_sel", i, "a_" + HOLD_CLIPS[i])
	var hold := AnimationNodeBlend2.new()
	_filter(hold, UPPER_BODY)
	bt.add_node("hold", hold)
	bt.connect_node("hold", 0, "hold_r")
	bt.connect_node("hold", 1, "hold_sel")

	var act_sel := AnimationNodeTransition.new()
	for i in ACTIONS.size():
		act_sel.add_input(ACTIONS[i])
		act_sel.set_input_reset(i, true)
		bt.add_node("x_" + ACTIONS[i], _anim(ACTIONS[i]))
	bt.add_node("act_sel", act_sel)
	for i in ACTIONS.size():
		bt.connect_node("act_sel", i, "x_" + ACTIONS[i])
	var act := AnimationNodeOneShot.new()
	act.fadein_time = 0.06
	act.fadeout_time = 0.16
	_filter(act, UPPER_BODY)
	bt.add_node("act", act)
	bt.connect_node("act", 0, "hold")
	bt.connect_node("act", 1, "act_sel")
	bt.connect_node("output", 0, "act")
	return bt


func _anim(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a


func _filter(node: AnimationNode, bones: Array[String]) -> void:
	node.filter_enabled = true
	for b in bones:
		node.set_filter_path(NodePath("%s:%s" % [_skeleton_path, b]), true)


# --- Clip choice (pure, tested) ---------------------------------------------------------------

## The full-body clip for this state: downed, climb, jump, fall, crouch, run, walk or idle.
static func base_clip(s: State) -> String:
	if s.downed:
		return "downed"
	if s.climbing:
		return "climb"
	if not s.on_floor:
		return "jump" if s.vertical > 0.5 else "fall"
	if s.crouching:
		return "crouch"
	if s.speed > RUN_ABOVE:
		return "run"
	if s.speed > 0.4:
		return "walk"
	return "idle"


## The upper-body hold blended over it: carry_shoulder (plank), carry_front (rail, wheel, panel), weld,
## hold_tool (any tool in the right hand) or "" (arms free).
static func hold_clip(s: State) -> String:
	if s.downed or s.climbing:
		return ""
	if s.carried == "plank":
		return "carry_shoulder"
	if s.carried != "":
		return "carry_front"
	if s.welding:
		return "weld"
	if s.tool in TOOLS_HELD:
		return "hold_tool"
	return ""


## The one-shot clip a tool use plays ("" if that tool has none).
static func action_clip(tool: String) -> String:
	return TOOL_ACTIONS.get(tool, "")


# --- Per frame -------------------------------------------------------------------------------------

func update_state(delta: float) -> void:
	var b := base_clip(state)
	if b != current_base:
		current_base = b
		if b in MOVE_CLIPS:
			set("parameters/move/transition_request", b)
			set("parameters/base/transition_request", "move")
		else:
			set("parameters/base/transition_request", b)
	var scale := 1.0
	if b == "walk":
		scale = clampf(state.speed / WALK_SPEED, 0.6, 1.7)
	elif b == "run":
		scale = clampf(state.speed / RUN_SPEED, 0.8, 1.5)
	set("parameters/move_speed/scale", scale)

	var h := hold_clip(state)
	current_hold = h
	var r_target := 1.0 if h == "hold_tool" else 0.0
	var both_target := 1.0 if h in HOLD_CLIPS else 0.0
	if h in HOLD_CLIPS:
		set("parameters/hold_sel/transition_request", h)
	var k := clampf(delta * 10.0, 0.0, 1.0)
	set("parameters/hold_r/blend_amount", lerpf(float(get("parameters/hold_r/blend_amount")), r_target, k))
	set("parameters/hold/blend_amount", lerpf(float(get("parameters/hold/blend_amount")), both_target, k))
	if state.downed and is_acting():
		set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Plays a one-shot upper-body action (see ACTIONS). Returns false for an unknown clip.
func play_action(clip: String) -> bool:
	if not clip in ACTIONS or state.downed:
		return false
	last_action = clip
	set("parameters/act_sel/transition_request", clip)
	set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func is_acting() -> bool:
	return bool(get("parameters/act/active"))
