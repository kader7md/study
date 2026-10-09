extends Node
## Character, appearance and mirror checks (runs headless):
##   godot --headless --path . res://tests/TestCharacter.tscn
## Appearance code round trip and save/load, the animation clip picked per state and per tool, the character model
## (one eye / mouth / accessory shown, actions play), and the train mirror opening the customise menu.
## Exit code 0 = all checks passed. Restores the saved look in user://settings.cfg afterwards.

var failures := 0


func _ready() -> void:
	var saved_look := str(Settings.get_value("profile", "look", ""))
	_appearance()
	_clips()
	await _model()
	await _mirror()
	Settings.set_value("profile", "look", saved_look)
	Settings.save()
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _appearance() -> void:
	print("Appearance")
	var a := Appearance.new()
	a.skin = 4
	a.eyes = "googly"
	a.eye_color = 2
	a.mouth = "teeth"
	a.accessory = "backpack"
	a.hat_color = 7
	a.outfit = 9
	var b := Appearance.decode(a.encode())
	check(b.equals(a) and b.eyes == "googly" and b.outfit == 9 and b.accessory == "backpack", "code round trip (%s)" % a.encode())
	var junk := Appearance.decode("s99.e:laser.c-3.m:??.a:crown.h.o5.zzz")
	check(junk.skin == Appearance.SKINS.size() - 1 and junk.eyes == "round" and junk.mouth == "smile"
		and junk.accessory == Appearance.new().accessory and junk.outfit == 5, "a broken code falls back to safe values")
	check(Appearance.decode("").encode() == Appearance.new().encode(), "an empty code is the default look")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var all_ok := true
	for i in 40:
		var r := Appearance.random(rng)
		all_ok = all_ok and Appearance.decode(r.encode()).equals(r)
	check(all_ok, "random looks are valid and survive the round trip")
	# save / load through Settings (user://settings.cfg [profile] look)
	Appearance.save_local(a)
	Settings.save()
	Settings.load_settings()
	check(Appearance.load_local().equals(a), "the look is saved and loaded again (Settings profile/look)")
	check(Net.my_look() == a.encode(), "Net sends the saved look")


func _clips() -> void:
	print("Animation clips")
	var s := CharacterAnimator.State.new()
	check(CharacterAnimator.base_clip(s) == "idle", "standing still: idle")
	s.speed = 4.5
	check(CharacterAnimator.base_clip(s) == "walk", "walking: walk")
	s.speed = 7.5
	check(CharacterAnimator.base_clip(s) == "run", "sprinting: run")
	s.on_floor = false
	s.vertical = 4.0
	check(CharacterAnimator.base_clip(s) == "jump", "going up: jump")
	s.vertical = -3.0
	check(CharacterAnimator.base_clip(s) == "fall", "coming down: fall")
	s.on_floor = true
	s.climbing = true
	check(CharacterAnimator.base_clip(s) == "climb", "climbing: climb")
	s.climbing = false
	s.downed = true
	check(CharacterAnimator.base_clip(s) == "downed" and CharacterAnimator.hold_clip(s) == "", "downed: lies down, arms free")
	s.downed = false
	s.speed = 0.0
	var expect := {"hammer": "hammer", "wrench": "wrench", "nail_gun": "nail_gun", "come_along": "crank", "welder": ""}
	var ok := true
	for tool: String in expect:
		ok = ok and CharacterAnimator.action_clip(tool) == expect[tool]
	check(ok, "every tool picks its own action clip (hammer, wrench, nail_gun, crank)")
	var clips := {}
	for tool: String in expect:
		if expect[tool] != "":
			clips[expect[tool]] = true
	check(clips.size() == 4, "the four tool actions are distinct clips")
	s.tool = "hammer"
	check(CharacterAnimator.hold_clip(s) == "hold_tool", "a tool in hand: hold_tool")
	s.welding = true
	s.tool = "welder"
	check(CharacterAnimator.hold_clip(s) == "weld", "welding: weld")
	s.carried = "plank"
	check(CharacterAnimator.hold_clip(s) == "carry_shoulder", "a plank: carry_shoulder (wins over the tool)")
	var front := true
	for item: String in ["rail", "wheel", "panel"]:
		s.carried = item
		front = front and CharacterAnimator.hold_clip(s) == "carry_front"
	check(front, "a rail, wheel or panel: carry_front")


func _model() -> void:
	print("Character model")
	var c := CharacterModel.new()
	add_child(c)
	var lib := c.anim_player.get_animation_library("")
	var missing: Array[String] = []
	for clip: String in CharacterAnimator.LOOPED + CharacterAnimator.ACTIONS + ["jump"]:
		if not lib.has_animation(clip):
			missing.append(clip)
	check(missing.is_empty(), "every animation clip is in character.glb %s" % str(missing))
	check(lib.get_animation("walk").loop_mode == Animation.LOOP_LINEAR and lib.get_animation("hammer").loop_mode == Animation.LOOP_NONE,
		"walk loops, hammer plays once")
	var a := Appearance.new()
	a.eyes = "sleepy"
	a.mouth = "open"
	a.accessory = "cap"
	c.apply_look(a)
	var shown: Array[String] = []
	for mi: MeshInstance3D in c.skeleton.find_children("*", "MeshInstance3D", true, false):
		if mi.visible and (mi.name.begins_with("Eyes_") or mi.name.begins_with("Mouth_") or mi.name.begins_with("Acc_") or mi.name == "Hair"):
			shown.append(String(mi.name))
	shown.sort()
	check(shown == ["Acc_cap", "Eyes_sleepy", "Mouth_open"], "one eye style, one mouth and the accessory are shown, the hair hides under the cap %s" % str(shown))
	var skin_mi: MeshInstance3D = c.skeleton.find_child("Body", true, false)
	var tinted := false
	for i in skin_mi.mesh.get_surface_count():
		if skin_mi.mesh.surface_get_material(i).resource_name == "Skin":
			var m := skin_mi.get_surface_override_material(i) as ShaderMaterial
			tinted = m != null and m.get_shader_parameter("albedo") == a.skin_color()
	check(tinted, "the skin takes the chosen colour")
	c.set_tool("hammer")
	c.anim.state.tool = "hammer"
	c.anim.state.speed = 4.0
	await _frames(3)
	check(c.anim.current_base == "walk" and c.anim.current_hold == "hold_tool", "the tree walks with the hammer held")
	c.play_tool("hammer")
	await _frames(2)
	check(c.anim.last_action == "hammer" and c.anim.is_acting(), "a hammer use plays the hammer swing")
	c.play_tool("come_along")
	await _frames(2)
	check(c.anim.last_action == "crank", "the come-along plays the crank pump")
	c.set_carried("rail")
	await _frames(2)
	check(c.anim.current_hold == "carry_front", "carrying a rail: carry_front")
	c.queue_free()


func _mirror() -> void:
	print("Mirror")
	Game.new_game(false)
	Game.world_sabotage = false
	var main: Node3D = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	var player: Player = main.player
	var mirror := main.find_child("Mirror", true, false) as Mirror
	check(mirror != null and mirror.get_parent() == Game.train.cars[2], "a mirror stands in the utility wagon")
	if mirror == null:
		return
	check(player.body != null and player.body.render_layers == 2, "the local player has a body on layer 2 (seen in the mirror)")
	# aim at it and press [E]: the menu opens on this screen
	player.focused = mirror
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	player._handle_input(ev)
	await _frames(2)
	var menu := get_tree().root.find_child("CustomizeMenu", true, false) as CustomizeMenu
	check(menu != null and menu.is_open and Game.is_ui_open(&"customize"), "[E] on the mirror opens the customise menu")
	check(player.net_action.begins_with("interact#"), "the player reaches out (interact action synced)")
	if menu == null:
		return
	check(menu.preview != null and menu.preview.is_inside_tree(), "the menu has a live 3D preview")
	menu.set_option("eyes", "angry")
	menu.set_option("accessory", "scarf")
	menu.set_option("outfit", 3)
	menu.save()
	await _frames(2)
	var saved := Appearance.load_local()
	check(saved.eyes == "angry" and saved.accessory == "scarf" and saved.outfit == 3, "Save stores the look in the settings")
	check(player.look == saved.encode(), "the player's synced look changes")
	check(not Game.ui_open, "the menu closed and gave the mouse back")
	await _frames(2)
	check(player.body.look.accessory == "scarf", "the player's own body (the mirror image) wears the new look")
	# tools play their action on the body and are sent to the others
	player.select_tool("wrench")
	player.use_tool()
	await _frames(2)
	check(player.net_action.begins_with("wrench#") and player.body.anim.last_action == "wrench", "using the wrench plays (and syncs) the wrench turn")
	main.queue_free()
	await _frames(2)
