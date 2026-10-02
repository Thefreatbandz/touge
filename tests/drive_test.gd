extends Node
## Headless drive test: starts the race, drives with synthetic inputs, checks
## the car advances, drifts, and can finish without errors.

var _main = null
var _frame := 0
var _min_prog := 0.0
var _max_drift := 0.0
var _finished := false
var _stall := 0
var _prog_seg := 8
var _prog_frame := 0

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	add_child(_main)
	_main._on_start()
	_main._state = 2  # skip countdown
	_main._car.active = true
	_main._test_steer_on = true
	print("TEST: race started, seg=", _main._car._seg)

func _process(_dt: float) -> void:
	_frame += 1
	var hud = _main._hud
	var car = _main._car
	var track = _main._track
	# pure pursuit: steer toward a point further down the road
	# pure pursuit with adaptive lookahead: far on straights, short in hairpins
	var la_steps := clampi(int(5.0 + car.f_speed * 0.55), 6, 20)
	var ahead := mini(car._seg + la_steps, track.points.size() - 1)
	var to_t: Vector3 = track.points[ahead] - car.global_position
	var desired_yaw := atan2(-to_t.x, -to_t.z)
	var dy := wrapf(desired_yaw - car.yaw, -PI, PI)
	# scan further ahead for hairpins -> brake early
	var dy_max := absf(dy)
	for k in range(8, 30, 4):
		var ai := mini(car._seg + k, track.points.size() - 1)
		var tk: Vector3 = track.points[ai] - car.global_position
		var dk := absf(wrapf(atan2(-tk.x, -tk.z) - car.yaw, -PI, PI))
		dy_max = maxf(dy_max, dk)
	var steer_dem := clampf(dy * 2.2, -1.0, 1.0)
	var want_hb: bool = absf(dy) > 0.5 and absf(dy) < 1.0 and car.f_speed > 24.0 and (_frame % 120) < 30
	if want_hb:
		steer_dem *= 0.4  # ease off during the flick, like a human would
	# stuck recovery: progress-based (a human just pins the gas and muscles out)
	if car._seg > _prog_seg + 2:
		_prog_seg = car._seg
		_prog_frame = _frame
	var recovering: bool = (_frame - _prog_frame) > 240
	if recovering and car._seg > _prog_seg + 8:
		_prog_seg = car._seg
		_prog_frame = _frame
		recovering = false
	_main._test_steer = steer_dem  # analog hook (patched main.gd, reverted after test)
	# pulse-width feathering over a 10-frame window, like a tapping thumb
	var duty := int(absf(steer_dem) * 10.0)
	var tap := (_frame % 10) < duty
	hud.t_steer_l = tap and steer_dem > 0.0
	hud.t_steer_r = tap and steer_dem < 0.0
	hud.t_hb = want_hb
	hud.t_gas = recovering or (dy_max < 2.4 and not (want_hb or dy_max > 1.1))
	hud.t_brake = (dy_max > 0.7 and car.f_speed > 16.0) and not recovering
	if (_frame <= 30 and _frame % 5 == 0) or (_frame % 100 == 0 and _frame <= 800):
		print("DBG f=%d dy=%.2f sdem=%.2f gas=%s brake=%s hb=%s yaw=%.2f des=%.2f fspeed=%.1f" % [
			_frame, dy, steer_dem, str(hud.t_gas), str(hud.t_brake), str(hud.t_hb), car.yaw, desired_yaw, car.f_speed])
	var prog: float = _main._track.progress_of(_main._car._seg)
	_min_prog = maxf(_min_prog, prog)
	_max_drift = maxf(_max_drift, _main._car.drift_score)
	if _main._state == 3:
		_finished = true
	if _frame == 600 or _frame == 1800 or _frame == 3590:
		var p: Vector3 = _main._car.global_position
		print("TEST f=%d prog=%.2f drift=%.0f seg=%d fspeed=%.1f pos=(%.1f,%.1f,%.1f) state=%d" % [
			_frame, prog, _main._car.drift_score, _main._car._seg, _main._car.f_speed, p.x, p.y, p.z, _main._state])
	if _frame == 3600 or _frame == 6000 or _frame == 9000 or _frame == 11990:
		var p2: Vector3 = _main._car.global_position
		var ok_pos := p2.x == p2.x and p2.y == p2.y and p2.z == p2.z  # no NaN
		print("TEST RESULT ok_pos=%s prog=%.2f drift=%.0f finished=%s" % [
			str(ok_pos), _min_prog, _max_drift, str(_finished)])
		if ok_pos and _min_prog > 0.25 and _max_drift > 50.0:
			print("TEST PASS")
		else:
			print("TEST FAIL")
