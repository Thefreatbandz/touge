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
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
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
	_track.generate(_seed)
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
	_car.connect("scraped", _on_scrape)
	if not _hud:
		_hud = HudScript.new()
		add_child(_hud)
		_hud.connect("start_pressed", _on_start)
		_hud.connect("restart_pressed", _on_restart)
	_hud.set_minimap_track(_track.points)
	_build_smoke()
	_build_rival_smoke()
	_player_done = false
	_rival_done = false
	_end_t = 0.0
	_rival_msg_t = -1.0
	_look_s = _car.global_position
	_cam.global_position = _car.global_position - _car.fwd() * 10.0 + Vector3(0, 4.0, 0)
	_cam.look_at(_car.global_position + Vector3(0, 1.0, 0))
	_hud.hide_results()
	_hud.set_hud(0.0, 0.0, 0.0, 0.0)
	_hud.set_battle(0.0, true)
	_hud.set_center("")

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
	_build_sparks()

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
			_car.drive(dt, steer, gas, brake, hb)
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
			# finishes
			if not _player_done and _car._seg >= _track.finish_idx:
				_player_done = true
				_player_time = _race_t
				_car.active = false
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
	var f := _car.fwd()
	var want := _car.global_position - f * 9.5 + Vector3(0, 3.7, 0)
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-6.0 * dt))
	var look := _car.global_position + f * 9.0 + Vector3(0, 1.2, 0)
	_look_s = _look_s.lerp(look, 1.0 - exp(-9.0 * dt))
	if _cam.global_position.distance_squared_to(_look_s) > 0.01:
		_cam.look_at(_look_s)
	var spd_ratio := clampf(_car.vel.length() / 56.0, 0.0, 1.0)
	_cam.fov = lerpf(_cam.fov, 68.0 + spd_ratio * 14.0, 1.0 - exp(-4.0 * dt))
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
