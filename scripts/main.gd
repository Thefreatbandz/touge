extends Node3D
## TOUGE: night mountain-pass drift time attack. Title -> countdown -> race -> results.

const TrackScript := preload("res://scripts/track.gd")
const CarScript := preload("res://scripts/car.gd")
const HudScript := preload("res://scripts/hud.gd")

enum State { TITLE, COUNTDOWN, RACING, FINISHED }

var _state := State.TITLE
var _track: TrackScript
var _car: CarScript
var _rival: CarScript
var _cam: Camera3D
var _hud: HudScript
var _smoke: CPUParticles3D
var _rival_smoke: CPUParticles3D
var _look_s := Vector3.ZERO
var _count_t := 0.0
var _count_n := 0
var _race_t := 0.0
var _seed := 0
var _best := 0.0
var _title_orbit := 0.0
var _go_t := 0.0
var _sparks: CPUParticles3D
var _rain := false
var _rain_fx: CPUParticles3D
var _nitro := 0.6
var _nitro_fx: CPUParticles3D
var _ghost: MeshInstance3D
var _ghost_data: Array = []  # [[Vector3 pos, float yaw], ...] at 10 Hz
var _rec_data: Array = []
var _rec_t := 0.0
const GHOST_PATH := "user://touge_ghost.dat"
var _photo := false
var _photo_yaw := 0.0
var _photo_pitch := 0.35
var _photo_dist := 13.0
var _dragging := false
var _drag_last := Vector2.ZERO
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _player_done := false
var _rival_done := false
var _player_time := 0.0
var _rival_time := 0.0
var _end_t := 0.0
var _rival_msg_t := -1.0

func _ready() -> void:
	_build_world_fx()
	_seed = randi()
	_build_race()
	_hud.show_title()
	_state = State.TITLE

func _build_world_fx() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	_sky_mat = sm
	sm.sky_top_color = Color(0.13, 0.14, 0.34)
	sm.sky_horizon_color = Color(0.98, 0.48, 0.20)
	sm.ground_bottom_color = Color(0.05, 0.035, 0.045)
	sm.ground_horizon_color = Color(0.35, 0.16, 0.10)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.55, 0.26, 0.13)
	env.fog_density = 0.0042
	env.glow_enabled = true
	env.glow_intensity = 0.85
	_refresh_weather()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# PS1 dither + RGB5 post (fullscreen, below HUD so UI stays crisp)
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 5
	add_child(fx_layer)
	var fx_rect := ColorRect.new()
	fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fx_mat := ShaderMaterial.new()
	fx_mat.shader = load("res://assets/shaders/ps1_dither.gdshader")
	fx_rect.material = fx_mat
	fx_layer.add_child(fx_rect)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.55, 0.28)
	sun.light_energy = 1.25
	sun.rotation = Vector3(-0.38, 0.85, 0.0)
	sun.shadow_enabled = false
	add_child(sun)
	_cam = Camera3D.new()
	_cam.far = 900.0
	add_child(_cam)

func _build_race() -> void:
	if _track:
		_track.queue_free()
	if _car:
		_car.queue_free()
	if _rival:
		_rival.queue_free()
	_track = TrackScript.new()
	add_child(_track)
	_track.generate(_seed, _rain)
	_car = CarScript.new()
	add_child(_car)
	_rival = CarScript.new()
	add_child(_rival)
	var pose: Array = _track.start_pose()
	var side: Vector3 = _track.sides[int(pose[2])]
	_car.setup(_track, int(pose[2]), pose[0] + side * 2.2, float(pose[1]))
	_rival.body_color = Color(0.85, 0.12, 0.10)
	_rival.glow_color = Color(1.0, 0.15, 0.10)
	_rival.setup(_track, int(pose[2]), pose[0] - side * 2.2, float(pose[1]))
	# wet asphalt in rain: less grip, spicier drifts
	_car.grip_base = 5.5 if _rain else 7.5
	_rival.grip_base = 5.5 if _rain else 7.5
	_car.connect("scraped", _on_scrape)
	if not _hud:
		_hud = HudScript.new()
		add_child(_hud)
		_hud.connect("start_pressed", _on_start)
		_hud.connect("restart_pressed", _on_restart)
		_hud.connect("rain_toggled", _on_rain_toggled)
		_hud.connect("photo_pressed", _on_photo)
	_hud.set_minimap_track(_track.points)
	_build_smoke()
	_build_rival_smoke()
	_player_done = false
	_rival_done = false
	_nitro = 0.6
	_photo = false
	_end_t = 0.0
	_rival_msg_t = -1.0
	_look_s = _car.global_position
	_cam.global_position = _car.global_position - _car.fwd() * 10.0 + Vector3(0, 4.0, 0)
	_cam.look_at(_car.global_position + Vector3(0, 1.0, 0))
	_hud.hide_results()
	_hud.set_hud(0.0, 0.0, 0.0, 0.0)
	_hud.set_battle(0.0, true)
	_hud.set_center("")
	_build_ghost()

func _build_ghost() -> void:
	# translucent replay of your last run
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_ghost_data.clear()
	_rec_data.clear()
	_rec_t = 0.0
	if FileAccess.file_exists(GHOST_PATH):
		var f := FileAccess.open(GHOST_PATH, FileAccess.READ)
		if f:
			_ghost_data = f.get_var()
			f.close()
	if _ghost_data.is_empty():
		return
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 0.62, 4.0)
	_ghost.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.90, 1.0, 0.38)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)

func _update_ghost() -> void:
	# record current run at 10 Hz
	_rec_t += get_process_delta_time()
	if _rec_t >= 0.1:
		_rec_t = 0.0
		_rec_data.append([_car.global_position, _car.yaw])
	# play back last run's ghost
	if is_instance_valid(_ghost) and not _ghost_data.is_empty():
		var idx := int(_race_t * 10.0)
		if idx < _ghost_data.size():
			var frame: Array = _ghost_data[idx]
			_ghost.global_position = (frame[0] as Vector3) + Vector3(0, 0.45, 0)
			_ghost.rotation.y = float(frame[1])
			_ghost.visible = true
		else:
			_ghost.visible = false

func _save_ghost() -> void:
	if _rec_data.size() < 50:
		return
	var f := FileAccess.open(GHOST_PATH, FileAccess.WRITE)
	if f:
		f.store_var(_rec_data)
		f.close()

func _build_smoke() -> void:
	_smoke = CPUParticles3D.new()
	_smoke.amount = 28
	_smoke.lifetime = 0.9
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.7
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 28.0
	_smoke.initial_velocity_min = 1.5
	_smoke.initial_velocity_max = 4.0
	_smoke.gravity = Vector3(0, 1.2, 0)
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.1
	_smoke.color = Color(0.55, 0.57, 0.62, 0.5)
	_smoke.position = Vector3(0, 0.35, 1.6)
	_smoke.emitting = false
	_car.add_child(_smoke)
	_build_nitro_fx()
	_build_sparks()

func _build_nitro_fx() -> void:
	# exhaust flames while nitro is burning
	_nitro_fx = CPUParticles3D.new()
	_nitro_fx.amount = 36
	_nitro_fx.lifetime = 0.35
	_nitro_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_nitro_fx.emission_sphere_radius = 0.25
	_nitro_fx.direction = Vector3(0, 0.3, 1)
	_nitro_fx.spread = 18.0
	_nitro_fx.initial_velocity_min = 7.0
	_nitro_fx.initial_velocity_max = 12.0
	_nitro_fx.gravity = Vector3.ZERO
	_nitro_fx.scale_amount_min = 0.18
	_nitro_fx.scale_amount_max = 0.34
	_nitro_fx.color = Color(1.0, 0.55, 0.15)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.40), Color(1.0, 0.25, 0.05, 0.0)])
	_nitro_fx.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.30, 0.30)
	_nitro_fx.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	_nitro_fx.emitting = false
	add_child(_nitro_fx)

func _build_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.5
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.4
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 60.0
	_sparks.initial_velocity_min = 4.0
	_sparks.initial_velocity_max = 10.0
	_sparks.gravity = Vector3(0, -14.0, 0)
	_sparks.scale_amount_min = 0.06
	_sparks.scale_amount_max = 0.14
	_sparks.color = Color(1.0, 0.75, 0.25)
	_sparks.position = Vector3(0, 0.5, 0)
	_sparks.emitting = false
	_car.add_child(_sparks)

func _build_rival_smoke() -> void:
	_rival_smoke = CPUParticles3D.new()
	_rival_smoke.amount = 28
	_rival_smoke.lifetime = 0.9
	_rival_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_rival_smoke.emission_sphere_radius = 0.7
	_rival_smoke.direction = Vector3(0, 1, 0)
	_rival_smoke.spread = 28.0
	_rival_smoke.initial_velocity_min = 1.5
	_rival_smoke.initial_velocity_max = 4.0
	_rival_smoke.gravity = Vector3(0, 1.2, 0)
	_rival_smoke.scale_amount_min = 0.5
	_rival_smoke.scale_amount_max = 1.1
	_rival_smoke.color = Color(0.55, 0.57, 0.62, 0.5)
	_rival_smoke.position = Vector3(0, 0.35, 1.6)
	_rival_smoke.emitting = false
	_rival.add_child(_rival_smoke)

func _on_start() -> void:
	_hud.hide_title()
	_state = State.COUNTDOWN
	_count_t = 0.0
	_count_n = 0
	Sfx.engine_on()

func _on_restart() -> void:
	_seed = randi()
	_build_race()
	_on_start()

func _on_rain_toggled(on: bool) -> void:
	# per-run weather: refresh sky/fog/particles, rebuild with wet grip + puddles
	_rain = on
	_refresh_weather()
	_build_race()

func _on_photo() -> void:
	# photo mode: only while racing; hides UI, drag to orbit
	if _state != State.RACING:
		return
	_photo = not _photo
	_hud.set_photo_ui(_photo)
	if _photo:
		_photo_yaw = _car.yaw
		_photo_pitch = 0.35
		_photo_dist = 13.0

func _input(event: InputEvent) -> void:
	if not _photo:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_last = event.position
	elif event is InputEventMouseMotion and _dragging:
		var d: Vector2 = event.position - _drag_last
		_drag_last = event.position
		_photo_yaw -= d.x * 0.008
		_photo_pitch = clampf(_photo_pitch + d.y * 0.006, 0.05, 1.2)
	elif event is InputEventScreenTouch:
		_dragging = event.pressed
		_drag_last = event.position
	elif event is InputEventScreenDrag and _dragging:
		var sd: Vector2 = event.position - _drag_last
		_drag_last = event.position
		_photo_yaw -= sd.x * 0.008
		_photo_pitch = clampf(_photo_pitch + sd.y * 0.006, 0.05, 1.2)

func _apply_rain(env: Environment, sm: ProceduralSkyMaterial) -> void:
	if not _rain:
		return
	# stormy dusk: dark slate sky, dense fog, dim sun
	sm.sky_top_color = Color(0.10, 0.11, 0.20)
	sm.sky_horizon_color = Color(0.35, 0.22, 0.28)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.05)
	sm.ground_horizon_color = Color(0.12, 0.10, 0.14)
	env.ambient_light_energy = 0.45
	env.fog_light_color = Color(0.25, 0.18, 0.22)
	env.fog_density = 0.0075
	env.glow_intensity = 1.15

func _refresh_weather() -> void:
	# restore sunset defaults, then layer rain on top if enabled
	var sm := _sky_mat
	sm.sky_top_color = Color(0.13, 0.14, 0.34)
	sm.sky_horizon_color = Color(0.98, 0.48, 0.20)
	sm.ground_bottom_color = Color(0.05, 0.035, 0.045)
	sm.ground_horizon_color = Color(0.35, 0.16, 0.10)
	_env.ambient_light_energy = 0.75
	_env.fog_light_color = Color(0.55, 0.26, 0.13)
	_env.fog_density = 0.0042
	_env.glow_intensity = 0.85
	_apply_rain(_env, sm)
	_build_rain_fx()

func _build_rain_fx() -> void:
	# rain streaks riding with the camera
	if _rain_fx:
		_rain_fx.queue_free()
		_rain_fx = null
	if not _rain:
		return
	_rain_fx = CPUParticles3D.new()
	_rain_fx.amount = 400
	_rain_fx.lifetime = 0.9
	_rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain_fx.emission_box_extents = Vector3(18, 10, 18)
	_rain_fx.direction = Vector3(0, -1, 0)
	_rain_fx.spread = 6.0
	_rain_fx.initial_velocity_min = 28.0
	_rain_fx.initial_velocity_max = 36.0
	_rain_fx.gravity = Vector3(0, -6, 0)
	_rain_fx.scale_amount_min = 0.03
	_rain_fx.scale_amount_max = 0.05
	_rain_fx.color = Color(0.65, 0.75, 0.90, 0.55)
	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 0.9, 0.03)
	_rain_fx.draw_pass_1 = streak
	_rain_fx.position = Vector3(0, 8, 0)
	_cam.add_child(_rain_fx)

func _on_scrape() -> void:
	Sfx.scrape()
	if _sparks:
		_sparks.restart()

func _process(dt: float) -> void:
	match _state:
		State.TITLE:
			_title_orbit += dt * 0.35
			var c := _car.global_position
			_cam.global_position = c + Vector3(cos(_title_orbit) * 11.0, 4.2, sin(_title_orbit) * 11.0)
			_cam.look_at(c + Vector3(0, 1.0, 0))
		State.COUNTDOWN:
			_count_t += dt
			var n := int(_count_t / 0.8)
			if n != _count_n:
				_count_n = n
				if n < 3:
					_hud.set_center(str(3 - n))
					Sfx.count_beep()
				else:
					_hud.set_center("GO!")
					Sfx.go_beep()
					_state = State.RACING
					_race_t = 0.0
					_car.active = true
					_rival.active = true
					_go_t = 0.0
			_follow_cam(dt)
		State.RACING:
			_race_t += dt
			_go_t += dt
			if _go_t > 1.2:
				_hud.set_center("")
			var steer := _hud.touch_steer()
			var gas := 1.0 if _hud.t_gas else 0.0
			var brake := 1.0 if _hud.t_brake else 0.0
			var hb := _hud.t_hb
			if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
				steer += 1.0
			if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
				steer -= 1.0
			if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
				gas = 1.0
			if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
				brake = 1.0
			if Input.is_key_pressed(KEY_SPACE):
				hb = true
			# nitro: refills by drifting, drains while held
			if _car.drifting and not _player_done:
				_nitro = minf(1.0, _nitro + dt * 0.14)
			var want_nitro := (_hud.t_nitro or Input.is_key_pressed(KEY_SHIFT)) \
				and _nitro > 0.05 and not _player_done
			if want_nitro:
				_nitro = maxf(0.0, _nitro - dt * 0.38)
			_hud.set_nitro(_nitro)
			_car.drive(dt, steer, gas, brake, hb, want_nitro)
			if _nitro_fx:
				_nitro_fx.emitting = want_nitro
				if want_nitro:
					_nitro_fx.position = _car.global_position - _car.fwd() * 2.3 + Vector3(0, 0.55, 0)
			var ai: Array = _ai_inputs()
			_rival.drive(dt, float(ai[0]), float(ai[1]), float(ai[2]), false)
			_follow_cam(dt)
			var spd_ratio := clampf(_car.vel.length() / 56.0, 0.0, 1.0)
			Sfx.set_engine(spd_ratio if not _player_done else 0.0)
			Sfx.set_drift(1.0 if _car.drifting and not _player_done else 0.0)
			_smoke.emitting = _car.drifting and not _player_done
			_rival_smoke.emitting = _rival.drifting
			_hud.set_hud(_race_t, _car.drift_score, _car.speed_kmh(),
				_track.progress_of(_car._seg))
			var pgap := (_track.progress_of(_rival._seg) - _track.progress_of(_car._seg)) * 1520.0
			_hud.set_battle(absf(pgap), pgap < 0.0)
			_hud.update_minimap(_car.global_position, _rival.global_position)
			_update_ghost()
			# finishes
			if not _player_done and _car._seg >= _track.finish_idx:
				_player_done = true
				_player_time = _race_t
				_car.active = false
				_save_ghost()
			if not _rival_done and _rival._seg >= _track.finish_idx:
				_rival_done = true
				_rival_time = _race_t
				_rival.active = false
				if not _player_done:
					_hud.set_center("RIVAL FINISHED!")
					_rival_msg_t = 0.0
			if _rival_msg_t >= 0.0:
				_rival_msg_t += dt
				if _rival_msg_t > 2.0:
					_hud.set_center("")
					_rival_msg_t = -1.0
			if _player_done or _rival_done:
				_end_t += dt
			var race_over := (_player_done and _rival_done) \
				or (_player_done and _end_t > 8.0) \
				or (_rival_done and _end_t > 30.0)
			if race_over:
				_finish_battle()
		State.FINISHED:
			_follow_cam(dt)
			_smoke.emitting = false

func _follow_cam(dt: float) -> void:
	if _photo:
		# free orbit around the car for screenshots
		var target := _car.global_position + Vector3(0, 1.0, 0)
		var off := Vector3(sin(_photo_yaw) * cos(_photo_pitch),
			sin(_photo_pitch), cos(_photo_yaw) * cos(_photo_pitch)) * _photo_dist
		_cam.global_position = _cam.global_position.lerp(target + off, 1.0 - exp(-8.0 * dt))
		if _cam.global_position.distance_squared_to(target) > 0.01:
			_cam.look_at(target)
		_cam.fov = lerpf(_cam.fov, 55.0, 1.0 - exp(-4.0 * dt))
		return
	var f := _car.fwd()
	var want := _car.global_position - f * 9.5 + Vector3(0, 3.7, 0)
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-6.0 * dt))
	var look := _car.global_position + f * 9.0 + Vector3(0, 1.2, 0)
	_look_s = _look_s.lerp(look, 1.0 - exp(-9.0 * dt))
	if _cam.global_position.distance_squared_to(_look_s) > 0.01:
		_cam.look_at(_look_s)
	var spd_ratio := clampf(_car.vel.length() / 56.0, 0.0, 1.0)
	var want_fov := 68.0 + spd_ratio * 14.0
	if _nitro_fx and _nitro_fx.emitting:
		want_fov = 95.0  # nitro warp
	_cam.fov = lerpf(_cam.fov, want_fov, 1.0 - exp(-4.0 * dt))
	# subtle speed shake
	if _state == State.RACING and spd_ratio > 0.55:
		var sh := (spd_ratio - 0.55) * 0.35
		var t := Time.get_ticks_msec() * 0.001
		_cam.global_position += Vector3(sin(t * 39.0) * sh * 0.4, cos(t * 47.0) * sh * 0.3, 0)

func _ai_inputs() -> Array:
	# pure-pursuit rival: short lookahead, aim off the wall, capped steer so the
	# power-slide never triggers (that was throwing it into the rails)
	var seg := _rival._seg
	var pos := _rival.global_position
	var speed := _rival.vel.length()
	var last := _track.points.size() - 1
	var look := clampi(int(5.0 + speed * 0.55), 6, 20)
	var ti := mini(seg + look, _track.finish_idx + 4)
	var target: Vector3 = _track.points[ti]
	var q: Vector3 = _track.query(pos, seg)
	var lat: float = q.y  # + = right of center
	if absf(lat) > 2.0:
		target -= _track.sides[ti] * signf(lat) * 2.5
	var to_t := target - pos
	to_t.y = 0.0
	var steer := 0.0
	if to_t.length_squared() > 0.01:
		var want_yaw := atan2(-to_t.x, -to_t.z)
		var dyaw := wrapf(want_yaw - _rival.yaw, -PI, PI)
		steer = clampf(dyaw * 2.4, -1.0, 1.0)
	if absf(lat) > 2.4:
		steer = clampf(steer + signf(lat) * 0.8, -1.0, 1.0)
	# cap steer at speed: full lock + speed = power-slide = wall
	if speed > 26.0:
		steer = clampf(steer, -0.72, 0.72)
	# curvature scan for braking
	var curve := 0.0
	var k := seg + 4
	var kend := mini(seg + 26, last)
	while k <= kend:
		curve = maxf(curve, absf(wrapf(_track.yaws[k] - _track.yaws[seg], -PI, PI)))
		k += 2
	var corner_speed := lerpf(52.0, 21.0, clampf(curve / 0.7, 0.0, 1.0))
	if absf(lat) > 3.2:
		corner_speed = minf(corner_speed, 24.0)
	var gap := _track.progress_of(_rival._seg) - _track.progress_of(_car._seg)
	var top := 49.0 + clampf(-gap * 300.0, -3.0, 4.0)
	var target_speed := minf(corner_speed, top)
	var gas := 1.0 if speed < target_speed else 0.0
	var brake := 1.0 if speed > target_speed + 5.0 else 0.0
	return [steer, gas, brake]

func _finish_battle() -> void:
	_state = State.FINISHED
	_car.active = false
	_rival.active = false
	Sfx.engine_off()
	Sfx.set_drift(0.0)
	Sfx.finish_jingle()
	var won := false
	var gap_s := 0.0
	if _player_done and _rival_done:
		won = _player_time < _rival_time
		gap_s = _player_time - _rival_time
	elif _player_done:
		won = true
		var dist_gap := (_track.progress_of(_car._seg) - _track.progress_of(_rival._seg)) * 1520.0
		gap_s = dist_gap / 45.0
	else:
		won = false
		gap_s = _race_t - _rival_time
	var new_best := false
	if _player_done and (_best <= 0.0 or _player_time < _best):
		_best = _player_time
		new_best = true
	_hud.show_results(won, _player_time if _player_done else _race_t,
		gap_s, _car.drift_score, _best, new_best)
	_burst_confetti(_car.global_position if _player_done else _rival.global_position)

func _burst_confetti(at: Vector3) -> void:
	# one-shot celebration burst at the finish
	var p := CPUParticles3D.new()
	p.amount = 120
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 38.0
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 16.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.22
	p.color = Color(1.0, 0.75, 0.25)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.35, 0.55), Color(0.30, 0.95, 1.0), Color(1.0, 0.85, 0.30)])
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	p.mesh = quad
	p.position = at + Vector3(0, 2.5, 0)
	add_child(p)
	p.emitting = true
	# clean up after the show
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(p.queue_free)
