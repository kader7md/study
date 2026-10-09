extends Node
## Preview screenshots of the quest map "The Mountain" (needs a display or xvfb-run, not --headless):
##   godot --path . --rendering-driver opengl3 res://tests/ScreenshotQuest.tscn -- <output_dir>
## Writes quest_*.png: the portal by the gate, an overview of the whole mountain, every biome, the gorge bridges,
## a climb with the stamina bar, a rope ladder, and the summit with the key. Prints "DONE n shots" at the end.

const L := preload("res://scripts/quest/mountain/mountain_layout.gd")

var main: Node3D
var out := "user://"
var cam: Camera3D
var shot_count := 0
var map: MountainMap
var player: Player


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var dir := DirAccess.open(out)
	if dir:
		for f in dir.get_files():
			if f.begins_with("quest_") and f.ends_with(".png"):
				dir.remove(f)
	tree_exiting.connect(func() -> void: print("DONE %d shots" % shot_count))
	Game.new_game(false)
	Game.world_sabotage = false
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	player = main.player
	var quest := Game.quest
	var portal := quest.get_node("Portal_2") as QuestPortal
	# 0. the trailhead portal beside the locked mountain-pass gate
	cam = Camera3D.new()
	cam.far = 4000.0
	main.add_child(cam)
	cam.make_current()
	main.hud.visible = false
	var gate := main.find_child("Gate_2", true, false) as Node3D
	_look(portal.global_position + portal.global_basis.z * 9.0 + portal.global_basis.x * 5.0 + Vector3.UP * 3.0, (portal.global_position + gate.global_position) * 0.5 + Vector3.UP * 1.5)
	await _shot("quest_0_portal", 1.0)
	quest.enter(2)
	await get_tree().create_timer(1.0).timeout
	map = quest.map as MountainMap
	cam.make_current()
	# 1. the whole mountain
	_look_local(Vector3(520, 260, 640), Vector3(0, 120, 0))
	await _shot("quest_1_overview", 1.5)
	_look_local(Vector3(-200, 60, 520), Vector3(0, 150, 0))
	await _shot("quest_1b_overview_south", 1.0)
	# 2. the beach camp
	var beach := L.camp_position(0)
	_look_local(beach + Vector3(14, 4, 14), beach + Vector3(-4, 1, -10))
	await _shot("quest_2_beach_camp")
	# 3. forest slope, looking up at the first cliffs
	_look_local(L.at(320, 0.15, 3.0), L.at(250, 0.0, 10.0))
	await _shot("quest_3_forest")
	# 4. the rock bands: cliffs, the chimney and a ramp
	var chim := L.riser_foot(2, -0.05, 14.0)
	_look_local(chim + Vector3.UP * 6.0 + L.outward(-0.05) * 6.0, L.riser_top(2, -0.05) + Vector3.UP * 2.0)
	await _shot("quest_4_cliffs_chimney")
	_look_local(L.at(262, 0.75, 14.0), L.at(250, 0.55, 6.0))
	await _shot("quest_4b_ramp")
	# 5. the gorge and the rope bridges
	_look_local(L.at(L.GORGE_OUT + 4.0, 0.12, 9.0), L.at(L.PILLAR_RP, 0.0, 22.0) - Vector3.UP * 4.0)
	await _shot("quest_5_gorge_bridges")
	# 6. jungle ledges and the overhang
	_look_local(L.at(176.0, 0.08, 6.0), L.riser_top(8, 0.0) + Vector3.UP * 1.0)
	await _shot("quest_6_jungle_overhang")
	# 7. snowfields and camp 4
	var c4 := L.camp_position(4)
	_look_local(c4 + L.outward(0.0) * 30.0 + Vector3(12, 14, 0), c4 + Vector3.UP * 4.0)
	await _shot("quest_7_snow")
	# 8. the summit with the key
	var top := L.summit()
	_look_local(top + Vector3(7, 3, 9), top + Vector3(0, 1.0, 0))
	await _shot("quest_8_summit_key", 0.8)
	# 9. climbing with the stamina bar (first person, HUD on)
	main.hud.visible = true
	player.camera.make_current()
	var th := -0.25
	var foot := L.riser_foot(0, th, 0.3)
	var hit := _ground(foot)
	foot.y = hit + 0.15 if hit > -INF else foot.y
	var look := L.at(L.boundary(0, th) - 3.0, th)
	var x := Transform3D(Basis.looking_at((map.to_global(look) - map.to_global(foot)) * Vector3(1, 0, 1)), map.to_global(foot))
	player.teleport(x)
	await get_tree().create_timer(0.5).timeout
	Input.action_press("climb")
	Input.action_press("move_forward")
	await get_tree().create_timer(3.2).timeout
	Input.action_release("move_forward")
	player.camera.rotation.x = 0.55
	await _shot("quest_9_climbing_stamina", 0.2)
	player.camera.rotation.x = -0.6
	await _shot("quest_9b_climbing_down_view", 0.2)
	Input.action_release("climb")
	player.camera.rotation.x = 0.0
	# 10. a rope ladder down a cliff
	var anchor := map.get_node("Anchor_0") as RopeAnchor
	anchor.interact(player)
	main.hud.visible = false
	cam.make_current()
	var lad := anchor.ladder
	_look((lad.bottom + lad.top) * 0.5 + anchor.out * 9.0 + Vector3.UP * 1.0 + Vector3(4, 0, 0), (lad.bottom + lad.top) * 0.5)
	await _shot("quest_10_rope_ladder", 0.6)
	get_tree().quit()


func _ground(local: Vector3) -> float:
	var from := map.to_global(local + Vector3.UP * 4.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0, Build.LAYER_WORLD)
	var hit := map.get_world_3d().direct_space_state.intersect_ray(q)
	return map.to_local(hit.position).y if hit else -INF


func _look(pos: Vector3, at: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(at, Vector3.UP)


func _look_local(pos: Vector3, at: Vector3) -> void:
	_look(map.to_global(pos), map.to_global(at))


func _shot(name: String, settle := 0.5) -> void:
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	shot_count += 1
	print("saved ", name)
