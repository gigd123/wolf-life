extends Node3D

# Independent of all gameplay code (see DESIGN.md "3D 視覺測試場景"). Only
# checks whether the正式版 look (3D scene + 2D pixel character, depth of
# field / glow / fog) is workable in Godot 4 — not meant to look finished.

func _ready() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.62, 0.68)
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.6, 0.65, 0.7)
	environment.fog_density = 0.03
	environment.glow_enabled = true
	environment.ssao_enabled = true
	env.environment = environment
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_texture = PixelArt.make_flat_texture(Vector2i(64, 64), Color(0.18, 0.3, 0.15), 42)
	ground_mat.uv1_scale = Vector3(8, 8, 1)
	ground.material_override = ground_mat
	add_child(ground)

	for i in range(6):
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.15
		cyl.bottom_radius = 0.2
		cyl.height = 3.0
		trunk.mesh = cyl
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = Color(0.25, 0.18, 0.12)
		trunk.material_override = trunk_mat
		trunk.position = Vector3(randf_range(-8, 8), 1.5, randf_range(-8, -2))
		add_child(trunk)

		var canopy := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.2
		sphere.height = 2.2
		canopy.mesh = sphere
		var canopy_mat := StandardMaterial3D.new()
		canopy_mat.albedo_color = Color(0.16, 0.32, 0.14)
		canopy.material_override = canopy_mat
		canopy.position = trunk.position + Vector3(0, 2.0, 0)
		add_child(canopy)

	var wolf_sprite := Sprite3D.new()
	wolf_sprite.texture = PixelArt.make_animal_sprite("gray_wolf", Vector2i(64, 40))
	wolf_sprite.pixel_size = 0.03
	wolf_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wolf_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wolf_sprite.position = Vector3(0, 0.6, 0)
	add_child(wolf_sprite)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.2, 6)
	camera.rotation_degrees = Vector3(-10, 0, 0)
	camera.current = true
	add_child(camera)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.position = Vector2(20, 20)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	canvas.add_child(back_btn)
