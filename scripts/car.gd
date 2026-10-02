extends Node3D
## Arcade drift car: custom physics (no VehicleBody sim), 90s panda coupe mesh.

signal scraped  # guardrail hit

const ENGINE_ACCEL := 24.0
const BRAKE_FORCE := 34.0
const MAX_SPEED := 56.0       # ~200 km/h
const MAX_REVERSE := 9.0
const DRAG := 0.28
const ROLLING := 1.6
const GRIP := 7.5
const DRIFT_GRIP := 1.1

var yaw := 0.0
var vel := Vector3.ZERO
var f_speed := 0.0            # signed forward speed
var steer_s := 0.0            # smoothed steer -1..1
var drifting := false
var slip_deg := 0.0
var drift_score := 0.0
var active := false           # false during countdown/title

var _body: Node3D
var _wheels: Array[Node3D] = []
var _wheel_spin: Array[MeshInstance3D] = []
var _track: Node = null
var _seg := 0
var _scrape_cd := 0.0

func fwd() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func setup(track: Node, seg: int, pos: Vector3, start_yaw: float) -> void:
	_track = track
	_seg = seg
	global_position = pos + Vector3(0, 0.02, 0)
	yaw = start_yaw
	vel = Vector3.ZERO
	f_speed = 0.0
	steer_s = 0.0
	drift_score = 0.0
	drifting = false
	rotation.y = yaw
	_build_mesh()

func drive(dt: float, steer: float, throttle: float, brake: float, handbrake: bool) -> void:
	if not active:
		return
	_scrape_cd = maxf(0.0, _scrape_cd - dt)
	# --- steering ---
	steer_s = lerpf(steer_s, clampf(steer, -1.0, 1.0), 1.0 - exp(-10.0 * dt))
	var spd := vel.length()
	var spd_ratio := clampf(spd / MAX_SPEED, 0.0, 1.0)
	var steer_max := lerpf(0.55, 0.13, spd_ratio)
	# steering authority: full once rolling, but never helpless at crawl speed
	# (arcade-forgiving: you can always muscle the nose around a hairpin)
	var auth := clampf(0.35 + spd / 10.0, 0.35, 1.0)
	var yaw_rate := steer_s * steer_max * auth * 2.3
	if handbrake:
		yaw_rate *= 1.35  # flick the tail out
	yaw += yaw_rate * dt
	var f := fwd()

	# --- longitudinal ---
	f_speed = vel.dot(f)
	if throttle > 0.0:
		f_speed += ENGINE_ACCEL * throttle * maxf(0.0, 1.0 - f_speed / MAX_SPEED) * dt
	if brake > 0.0:
		if f_speed > 1.0:
			f_speed -= BRAKE_FORCE * brake * dt
		else:
			f_speed -= ENGINE_ACCEL * 0.5 * brake * dt  # reverse
	f_speed = clampf(f_speed, -MAX_REVERSE, MAX_SPEED * 1.05)
	f_speed -= f_speed * DRAG * dt
	if absf(f_speed) < ROLLING * dt * 4.0 and throttle <= 0.0:
		f_speed = 0.0
	else:
		f_speed -= signf(f_speed) * ROLLING * dt

	# --- lateral grip: low grip + steering = drift ---
	var lat := vel - f * vel.dot(f)
	var grip := DRIFT_GRIP if handbrake else GRIP
	if absf(steer_s) > 0.75 and spd > 26.0:
		grip *= 0.55  # power slide at full lock + speed
	lat *= exp(-grip * dt)
	vel = f * f_speed + lat

	# --- integrate + rails ---
	global_position += vel * dt
	var q: Vector3 = _track.query(global_position, _seg)
	_seg = int(q.x)
	var lat_off: float = q.y
	var lim := 5.0 - 0.95
	if absf(lat_off) > lim:
		var side: Vector3 = _track.sides[_seg]
		# strip the lateral component, re-add clamped: hard rail, no tunneling
		global_position = _track.points[_seg] + side * (lim * signf(lat_off)) \
			+ (global_position - _track.points[_seg] - side * lat_off)
		# kill outward velocity, scrub a little speed, rattle
		var outward := side * signf(lat_off)
		var v_out := vel.dot(outward)
		if v_out > 0.0:
			vel -= outward * v_out * 1.6
		f_speed *= 0.97
		vel *= 0.995
		if _scrape_cd <= 0.0 and spd > 6.0:
			_scrape_cd = 0.5
			emit_signal("scraped")

	# --- drift state + scoring ---
	spd = vel.length()
	if spd > 0.5:
		var ang := rad_to_deg(fwd().angle_to(vel.normalized()))
		slip_deg = ang
	else:
		slip_deg = 0.0
	drifting = spd > 9.0 and (handbrake or slip_deg > 13.0)
	if drifting:
		drift_score += spd * slip_deg * dt * 0.9

	# --- visuals ---
	rotation.y = yaw
	var target_roll := clampf(-yaw_rate * spd * 0.012, -0.09, 0.09)
	var target_pitch := clampf(-(f_speed - _last_f) * 0.02, -0.05, 0.06)
	_last_f = f_speed
	_body.rotation.z = lerpf(_body.rotation.z, target_roll, 1.0 - exp(-8.0 * dt))
	_body.rotation.x = lerpf(_body.rotation.x, target_pitch, 1.0 - exp(-8.0 * dt))
	for i in range(_wheels.size()):
		_wheels[i].rotation.x += f_speed / 0.34 * dt
		if i < 2:  # front wheels steer
			_wheels[i].rotation.y = steer_s * steer_max

var _last_f := 0.0

func speed_kmh() -> float:
	return absf(f_speed) * 3.6

# --- 90s panda coupe ----------------------------------------------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.55
	m.metallic = 0.25
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_mesh() -> void:
	if _body:
		_body.queue_free()
	_body = Node3D.new()
	add_child(_body)
	var white := Color(0.92, 0.92, 0.94)
	var black := Color(0.05, 0.05, 0.06)
	var glass := Color(0.06, 0.09, 0.13)
	# lower body (panda white)
	_box(_body, Vector3(1.82, 0.62, 4.3), Vector3(0, 0.62, 0), white)
	# black hood (panda style)
	_box(_body, Vector3(1.84, 0.10, 1.35), Vector3(0, 0.95, -1.42), black)
	# cabin / glasshouse
	_box(_body, Vector3(1.58, 0.52, 2.05), Vector3(0, 1.12, 0.25), glass)
	# roof panel (white)
	_box(_body, Vector3(1.60, 0.08, 1.15), Vector3(0, 1.40, 0.30), white)
	# trunk spoiler
	_box(_body, Vector3(1.70, 0.07, 0.42), Vector3(0, 1.18, 1.95), black)
	_box(_body, Vector3(0.08, 0.28, 0.30), Vector3(-0.70, 1.02, 1.95), black)
	_box(_body, Vector3(0.08, 0.28, 0.30), Vector3(0.70, 1.02, 1.95), black)
	# bumpers
	_box(_body, Vector3(1.88, 0.34, 0.35), Vector3(0, 0.42, -2.12), black)
	_box(_body, Vector3(1.88, 0.34, 0.35), Vector3(0, 0.42, 2.12), black)
	# pop-up headlights (up) + glow
	_box(_body, Vector3(0.42, 0.16, 0.42), Vector3(-0.58, 1.00, -1.95), black)
	_box(_body, Vector3(0.42, 0.16, 0.42), Vector3(0.58, 1.00, -1.95), black)
	_box(_body, Vector3(0.34, 0.10, 0.06), Vector3(-0.58, 1.00, -2.16),
		Color(1.0, 0.95, 0.75), 2.5)
	_box(_body, Vector3(0.34, 0.10, 0.06), Vector3(0.58, 1.00, -2.16),
		Color(1.0, 0.95, 0.75), 2.5)
	# taillight bar
	_box(_body, Vector3(1.55, 0.14, 0.06), Vector3(0, 0.78, 2.30),
		Color(1.0, 0.08, 0.08), 2.0)
	# wheels
	_wheels.clear()
	var tire := Color(0.04, 0.04, 0.045)
	for wx in [-0.82, 0.82]:
		for wz in [-1.35, 1.35]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, 0.34, wz)
			_body.add_child(pivot)
			var wm := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.34
			cm.bottom_radius = 0.34
			cm.height = 0.26
			wm.mesh = cm
			var tm := StandardMaterial3D.new()
			tm.albedo_color = tire
			tm.roughness = 0.95
			wm.material_override = tm
			wm.rotation.z = PI / 2.0
			pivot.add_child(wm)
			_wheels.append(pivot)
	# headlight beam
	var beam := SpotLight3D.new()
	beam.position = Vector3(0, 1.0, -1.8)
	beam.rotation.x = -0.06
	beam.light_color = Color(1.0, 0.94, 0.80)
	beam.light_energy = 5.0
	beam.spot_range = 55.0
	beam.spot_angle = 26.0
	beam.shadow_enabled = false
	_body.add_child(beam)
