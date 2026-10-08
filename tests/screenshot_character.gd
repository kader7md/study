extends Node
## Character preview pictures (needs a display or xvfb-run, not --headless):
##   godot --path . --rendering-driver opengl3 res://tests/ScreenshotCharacter.tscn -- <out_dir> [model|anims|game]
## model: turntable, every eye / mouth style, every accessory (contact sheets: char_*.png)
## anims: frames of every animation clip (anim_*.png)
## game:  the mirror on the train and its customise menu, other players in game, first-person arms (game_*.png)

var out := "user://"
var cam: Camera3D
var world: Node3D
var shot_count := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	tree_exiting.connect(func() -> void: print("DONE %d shots" % shot_count))
	if args.has("game") or args.has("remote"):
		await _game_shots(args.has("remote"))
		get_tree().quit()
		return
	_stage()
	if not args.has("anims"):
		await _model_shots()
	if args.has("anims") or not args.has("model"):
		await _anim_shots()
	get_tree().quit()


## A small photo studio: warm floor, sky, a sun and a fill light.
func _stage() -> void:
	world = Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("bcd7e6")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("dfe7f0")
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 6.0  # like the game world (main.gd): bright colours keep their hue
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	floor_mesh.material_override = Build.material(Color("d8c3a0"))
	world.add_child(floor_mesh)
	cam = Camera3D.new()
	cam.fov = 35.0
	world.add_child(cam)
	cam.make_current()


func _character(look: Appearance, pos := Vector3.ZERO, yaw := 0.0) -> CharacterModel:
	var c := CharacterModel.new()
	world.add_child(c)
	c.position = pos
	c.rotation.y = yaw
	c.apply_look(look)
	return c


func _model_shots() -> void:
	# turntable of the default look
	var c := _character(Appearance.new())
	cam.position = Vector3(0, 1.0, 4.2)
	cam.look_at(Vector3(0, 0.9, 0))
	var frames: Array[Image] = []
	for k in 6:
		c.rotation.y = TAU * k / 6.0 + PI
		frames.append(await _grab(Rect2i(560, 60, 480, 780)))
	_sheet("char_1_turntable", frames, 6)
	c.queue_free()
	# eyes and mouths: close-ups
	frames.clear()
	cam.position = Vector3(0, 1.45, 1.6)
	cam.look_at(Vector3(0, 1.4, 0))
	var labels: Array[String] = []
	for eyes: String in Appearance.EYES:
		var a := Appearance.new()
		a.eyes = eyes
		a.accessory = "none"
		a.eye_color = Appearance.EYES.find(eyes) % Appearance.EYE_COLORS.size()
		var m := _character(a, Vector3.ZERO, PI + 0.25)
		frames.append(await _grab(Rect2i(500, 120, 600, 600)))
		m.queue_free()
	for mouth: String in Appearance.MOUTHS:
		var a := Appearance.new()
		a.mouth = mouth
		a.accessory = "none"
		a.skin = Appearance.MOUTHS.find(mouth)
		var m := _character(a, Vector3.ZERO, PI - 0.25)
		frames.append(await _grab(Rect2i(500, 120, 600, 600)))
		m.queue_free()
	_sheet("char_2_faces", frames, 6)
	# accessories, each with another hat and outfit colour
	frames.clear()
	cam.position = Vector3(0, 1.1, 3.4)
	cam.look_at(Vector3(0, 1.0, 0))
	for i in Appearance.ACCESSORIES.size():
		var a := Appearance.new()
		a.accessory = Appearance.ACCESSORIES[i]
		a.hat_color = (i * 3 + 1) % Appearance.COLORS.size()
		a.outfit = i % Appearance.COLORS.size()
		a.skin = (i * 2) % Appearance.SKINS.size()
		a.eyes = Appearance.EYES[i % Appearance.EYES.size()]
		a.mouth = Appearance.MOUTHS[i % Appearance.MOUTHS.size()]
		var m := _character(a, Vector3.ZERO, PI + (0.5 if i % 2 == 0 else -0.6))
		frames.append(await _grab(Rect2i(560, 80, 480, 760)))
		m.queue_free()
	_sheet("char_3_accessories", frames, 4)
	# a crew line-up of random looks
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 5:
		var m := _character(Appearance.random(rng), Vector3((i - 2) * 0.95, 0, -absf(i - 2) * 0.3), PI + (2 - i) * 0.18)
		m.anim.state.speed = 0.0
	cam.fov = 40.0
	cam.position = Vector3(0, 1.3, 6.0)
	cam.look_at(Vector3(0, 0.9, 0))
	await get_tree().create_timer(0.6).timeout
	var img := await _grab(Rect2i(0, 0, 1600, 900))
	img.save_png("%s/char_4_crew.png" % out)
	shot_count += 1
	for ch in world.get_children():
		if ch is CharacterModel:
			ch.queue_free()
	cam.fov = 35.0


## Frames of every clip, posed straight from the AnimationPlayer (tree off), with the matching tool / item.
func _anim_shots() -> void:
	var clips := [
		["idle", "", "", [0.0, 1.0]], ["walk", "", "", [0.0, 0.16, 0.31, 0.47]], ["run", "", "", [0.0, 0.12, 0.23, 0.35]],
		["jump", "", "", [0.0, 0.12, 0.35]], ["fall", "", "", [0.0]], ["crouch", "", "", [0.0]],
		["carry_shoulder", "", "plank", [0.0]], ["carry_front", "", "rail", [0.0]], ["carry_front", "", "wheel", [0.0]],
		["carry_front", "", "panel", [0.0]], ["hold_tool", "hammer", "", [0.0]],
		["hammer", "hammer", "", [0.0, 0.16, 0.24, 0.3]], ["wrench", "wrench", "", [0.15, 0.32]],
		["nail_gun", "nail_gun", "", [0.0, 0.04]], ["weld", "welder", "", [0.0]], ["crank", "come_along", "", [0.2, 0.38]],
		["shovel", "", "", [0.3, 0.55]], ["lever", "", "", [0.15, 0.4]], ["interact", "", "", [0.14]],
		["wave", "", "", [0.2, 0.4]], ["downed", "", "", [0.0]], ["climb", "", "", [0.0, 0.4]],
	]
	var c := _character(Appearance.new(), Vector3.ZERO, PI + 0.6)
	c.anim.active = false
	cam.position = Vector3(0, 1.0, 4.4)
	cam.look_at(Vector3(0, 0.85, 0))
	var frames: Array[Image] = []
	var page := 1
	for entry: Array in clips:
		c.set_carried("")
		c.set_tool(entry[1])
		c.set_carried(entry[2])
		for t: float in entry[3]:
			if entry[0] == "shovel" and c.find_child("Shovel", true, false) == null:
				c._show_shovel()
			c.anim_player.play(entry[0])
			c.anim_player.seek(t, true)
			c.anim_player.pause()
			await get_tree().process_frame
			var img := await _grab(Rect2i(560, 40, 480, 820))
			_label(img, "%s %.2f" % [entry[0], t])
			frames.append(img)
			if frames.size() == 12:
				_sheet("anim_%d" % page, frames, 6)
				frames.clear()
				page += 1
	if frames.size() > 0:
		_sheet("anim_%d" % page, frames, 6)
	c.queue_free()


func _game_shots(remote_only := false) -> void:
	Game.new_game(false)
	Game.world_sabotage = false
	var main: Node3D = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	var player: Player = main.player
	var train := Game.train
	player.set_physics_process(false)
	# the mirror in the utility wagon, seen in first person
	var mirror := main.find_child("Mirror", true, false) as Mirror
	if mirror == null:
		push_error("no mirror on the train")
		return
	var front := mirror.global_transform * Vector3(0, 0, 1.7)
	player.global_position = Vector3(front.x, mirror.global_position.y - 1.55, front.z)
	player.look_at(Vector3(mirror.global_position.x, player.global_position.y, mirror.global_position.z), Vector3.UP)
	player.camera.rotation.x = -0.05
	player.camera.make_current()
	await get_tree().create_timer(1.0).timeout
	if remote_only:
		await _remote_shots(main, player, train)
		return
	await _save("game_1_mirror")
	mirror.interact_local(player)
	await get_tree().create_timer(1.2).timeout
	await _save("game_2_customise")
	var menu := get_tree().root.find_child("CustomizeMenu", true, false) as CustomizeMenu
	if menu:
		menu.randomise()
		menu.preview_yaw = PI + 0.9
		await get_tree().create_timer(0.8).timeout
		await _save("game_3_customise_random")
		menu.close()
	await get_tree().create_timer(0.3).timeout
	await _remote_shots(main, player, train)


func _remote_shots(main: Node3D, player: Player, train: Train) -> void:
	# other players: three remote crew members on the train platform doing different things
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bodies: Array[RemoteBody] = []
	var t := Game.track.transform_at(train.distance + 4.0)
	var acts := [["hammer", ""], ["", "plank"], ["welder", ""], ["", "wheel"]]
	for i in acts.size():
		var rb := RemoteBody.new()
		main.add_child(rb)
		rb.setup("Crew %d" % (i + 1), Net.COLORS[i])
		rb.set_look(Appearance.random(rng).encode())
		rb.global_position = t.origin + t.basis.x * (3.0 + (i % 2) * 1.4) - t.basis.z * (i * 1.3) + Vector3.UP * 0.05
		rb.rotation.y = t.basis.get_euler().y + (0.5 if i % 2 == 0 else -0.4) + PI
		rb.set_held(acts[i][0], acts[i][1])
		bodies.append(rb)
	bodies[2].set_welding(true)
	var free_cam := Camera3D.new()
	main.add_child(free_cam)
	free_cam.global_position = t.origin + t.basis.x * 6.5 + t.basis.z * 3.5 + Vector3.UP * 2.0
	free_cam.look_at(t.origin + t.basis.x * 3.5 - t.basis.z * 2.0 + Vector3.UP * 0.9)
	free_cam.make_current()
	main.hud.visible = false
	for k in 10:
		for rb in bodies:
			rb.animate(0.1, 0.0)
		await get_tree().process_frame
	bodies[0].play_action("hammer")
	await get_tree().create_timer(0.17).timeout
	await _save("game_4_remote_players")
	for k in 12:
		for i in bodies.size():
			bodies[i].animate(0.1, 3.0 if i == 1 else 0.0)
		await get_tree().process_frame
	await _save("game_5_remote_walk")
	# first-person arms (skin and sleeve follow the look)
	main.hud.visible = true
	player.camera.make_current()
	var plat := Game.track.transform_at(Game.track.station_distances[0])
	player.global_position = plat.origin + plat.basis.x * 3.5 + Vector3.UP * 1.4
	player.camera.rotation.x = -0.15
	await get_tree().create_timer(0.6).timeout
	await _save("game_6_fp_hammer")
	player.select_tool("wrench")
	await get_tree().create_timer(0.6).timeout
	player.viewmodel.play("wrench")
	await get_tree().create_timer(0.2).timeout
	await _save("game_7_fp_wrench")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	shot_count += 1
	print("saved ", name)


func _grab(rect: Rect2i) -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	return img.get_region(rect)


## Writes a little label into the corner of `img` (dark bar; the text itself is the file sheet order).
func _label(img: Image, _text: String) -> void:
	img.fill_rect(Rect2i(0, img.get_height() - 8, img.get_width(), 8), Color(0.2, 0.15, 0.1))


func _sheet(name: String, frames: Array[Image], cols: int) -> void:
	if frames.is_empty():
		return
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var rows := ceili(frames.size() / float(cols))
	var sheet := Image.create(w * mini(cols, frames.size()), h * rows, false, frames[0].get_format())
	sheet.fill(Color.WHITE)
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	if sheet.get_width() > 2400:
		sheet.resize(2400, int(sheet.get_height() * 2400.0 / sheet.get_width()))
	sheet.save_png("%s/%s.png" % [out, name])
	shot_count += 1
	print("saved ", name)
