extends Node3D
## TOUGE: night mountain-pass drift time attack. Title -> countdown -> race -> results.

const TrackScript := preload("res://scripts/track.gd")
const CarScript := preload("res://scripts/car.gd")
const HudScript := preload("res://scripts/hud.gd")

enum State { TITLE, COUNTDOWN, RACING, FINISHED }

var _state := State.TITLE
var _track: TrackScript
var _car: CarScript
var _cam: Camera3D
var _hud: HudScript
var _smoke: CPUParticles3D
var _look_s := Vector3.ZERO
var _count_t := 0.0
var _count_n := 0
var _race_t := 0.0
var _seed := 0
var _best := 0.0
var _title_orbit := 0.0
var _go_t := 0.0

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
	sm.sky_top_color = Color(0.006, 0.010, 0.028)
	sm.sky_horizon_color = Color(0.030, 0.052, 0.105)
	sm.ground_bottom_color = Color(0.004, 0.006, 0.012)
	sm.ground_horizon_color = Color(0.018, 0.030, 0.058)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.020, 0.036, 0.072)
	env.fog_density = 0.0052
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.60, 0.72, 0.98)
	moon.light_energy = 0.65
	moon.rotation = Vector3(-0.9, 0.6, 0.0)
	moon.shadow_enabled = false
	add_child(moon)
	_cam = Camera3D.new()
	_cam.far = 900.0
	add_child(_cam)

func _build_race() -> void:
	if _track:
		_track.queue_free()
	if _car:
		_car.queue_free()
	_track = TrackScript.new()
	add_child(_track)
	_track.generate(_seed)
	_car = CarScript.new()
	add_child(_car)
	var pose: Array = _track.start_pose()
	_car.setup(_track, int(pose[2]), pose[0], float(pose[1]))
	_car.connect("scraped", _on_scrape)
	if not _hud:
		_hud = HudScript.new()
		add_child(_hud)
		_hud.connect("start_pressed", _on_start)
		_hud.connect("restart_pressed", _on_restart)
	_build_smoke()
	_look_s = _car.global_position
	_cam.global_position = _car.global_position - _car.fwd() * 10.0 + Vector3(0, 4.0, 0)
	_cam.look_at(_car.global_position + Vector3(0, 1.0, 0))
	_hud.hide_results()
	_hud.set_hud(0.0, 0.0, 0.0, 0.0)
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
			_follow_cam(dt)
			var spd_ratio := clampf(_car.vel.length() / 56.0, 0.0, 1.0)
			Sfx.set_engine(spd_ratio)
			Sfx.set_drift(1.0 if _car.drifting else 0.0)
			_smoke.emitting = _car.drifting
			_hud.set_hud(_race_t, _car.drift_score, _car.speed_kmh(),
				_track.progress_of(_car._seg))
			if _car._seg >= _track.finish_idx:
				_finish()
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

func _finish() -> void:
	_state = State.FINISHED
	_car.active = false
	Sfx.engine_off()
	Sfx.set_drift(0.0)
	Sfx.finish_jingle()
	var new_best := false
	if _best <= 0.0 or _race_t < _best:
		_best = _race_t
		new_best = true
	_hud.show_results(_race_t, _car.drift_score, _best, new_best)
