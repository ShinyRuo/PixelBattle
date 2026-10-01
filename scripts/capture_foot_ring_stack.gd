extends SceneTree


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("202633")
	backdrop.size = root.content_scale_size
	root.add_child(backdrop)
	var glow := PBBuffGlow.new()
	backdrop.add_child(glow)
	glow.position = Vector2(320, 265)
	var drawings: Array[Dictionary] = []
	for id: StringName in [
		&"bond_team_seven_aura", &"bond_art_duo_aura", &"bond_immortal_pair_aura"
	]:
		drawings.append({"skin": PBBuffGlow.skin_for(id), "frame": 0})
	glow._set_drawings(drawings)
	var actor := Sprite2D.new()
	actor.texture = load("res://assets/actors/naruto/idle_0.png")
	actor.centered = false
	actor.position = glow.position - Vector2(164, 192)
	backdrop.add_child(actor)
	await process_frame
	await process_frame
	var snapshot := root.get_texture().get_image()
	snapshot.save_png("res://build/foot_ring_stack.png")
	quit()
