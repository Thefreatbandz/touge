extends Node3D
## Arcade drift car: custom physics (no VehicleBody sim), 90s panda coupe mesh.

signal scraped  # guardrail hit

const ENGINE_ACCEL := 24.0
const BRAKE_FORCE := 34.0
const MAX_SPEED := 56.0       # ~200 km/h
const MAX_REVERSE := 9.0
const DRAG := 0.28
const ROLLING := 1.6
var grip_base := 7.5  # lowered in rain for spicier drifts
const DRIFT_GRIP := 1.1

var yaw := 0.0
var vel := Vector3.ZERO
var f_speed := 0.0            # signed forward speed
var steer_s := 0.0            # smoothed steer -1..1
var drifting := false
var slip_deg := 0.0
var drift_score := 0.0
var active := false           # false during countdown/title
var body_color := Color(0.92, 0.92, 0.94)  # set before setup() for rival paint
var glow_color := Color(0.25, 0.9, 1.0)    # underglow tint (rival: red)

const TRAIL_MAX := 220
var _trail_pts: Array = []  # [Vector3 left, Vector3 right]
var _trail_mi: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _trail_fade := 0.0
var _ltrail_pts: Array = []  # light trails: [Vector3 left_tail, Vector3 right_tail]
var _ltrail_mi: MeshInstance3D
var _ltrail_mat: StandardMaterial3D
const LTRAIL_MAX := 36

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
	_build_trail()
	_build_ltrail()
	_build_underglow()

func drive(dt: float, steer: float, throttle: float, brake: float, handbrake: bool, boost := false) -> void:
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
	var top := MAX_SPEED * (1.35 if boost else 1.0)
	if throttle > 0.0:
		var accel := ENGINE_ACCEL * (1.9 if boost else 1.0)
		f_speed += accel * throttle * maxf(0.0, 1.0 - f_speed / top) * dt
	if brake > 0.0:
		if f_speed > 1.0:
			f_speed -= BRAKE_FORCE * brake * dt
		else:
			f_speed -= ENGINE_ACCEL * 0.5 * brake * dt  # reverse
	f_speed = clampf(f_speed, -MAX_REVERSE, top * 1.05)
	f_speed -= f_speed * DRAG * dt
	if absf(f_speed) < ROLLING * dt * 4.0 and throttle <= 0.0:
		f_speed = 0.0
	else:
		f_speed -= signf(f_speed) * ROLLING * dt

	# --- lateral grip: low grip + steering = drift ---
	var lat := vel - f * vel.dot(f)
	var grip := DRIFT_GRIP if handbrake else grip_base
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
	_update_trail(dt)
	_update_ltrail(dt)

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
	var white := body_color
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
	beam.light_energy = 9.0
	beam.spot_range = 75.0
	beam.spot_angle = 32.0
	beam.shadow_enabled = false
	_body.add_child(beam)
	# visible headlight cones (additive "volume" at dusk)
	var cone_mat := StandardMaterial3D.new()
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cone_mat.albedo_color = Color(1.0, 0.92, 0.72, 0.10)
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for hx in [-0.58, 0.58]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 1.35
		cm.height = 7.0
		cm.radial_segments = 10
		cone.mesh = cm
		cone.material_override = cone_mat
		cone.position = Vector3(hx, 0.92, -5.6)
		cone.rotation.x = PI / 2.0
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(cone)
	# --- detail pass: rims, mirrors, skirts, lip, exhaust ---
	var rim_c := Color(0.75, 0.77, 0.80)
	for pivot in _wheels:
		var rim := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.19
		rm.bottom_radius = 0.19
		rm.height = 0.28
		rim.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = rim_c
		rmat.metallic = 0.7
		rmat.roughness = 0.35
		rim.material_override = rmat
		rim.rotation.z = PI / 2.0
		pivot.add_child(rim)
	# side mirrors
	_box(_body, Vector3(0.16, 0.10, 0.12), Vector3(-0.92, 1.18, -0.55), black)
	_box(_body, Vector3(0.16, 0.10, 0.12), Vector3(0.92, 1.18, -0.55), black)
	# side skirts
	_box(_body, Vector3(0.10, 0.16, 2.9), Vector3(-0.93, 0.32, 0.1), black)
	_box(_body, Vector3(0.10, 0.16, 2.9), Vector3(0.93, 0.32, 0.1), black)
	# front lip
	_box(_body, Vector3(1.86, 0.12, 0.30), Vector3(0, 0.22, -2.20), black)
	# exhaust tip
	var ex := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.07
	em.bottom_radius = 0.07
	em.height = 0.22
	ex.mesh = em
	var exmat := StandardMaterial3D.new()
	exmat.albedo_color = Color(0.6, 0.62, 0.65)
	exmat.metallic = 0.8
	exmat.roughness = 0.3
	ex.material_override = exmat
	ex.rotation.x = PI / 2.0
	ex.position = Vector3(0.55, 0.30, 2.28)
	_body.add_child(ex)

func _build_trail() -> void:
	if _trail_mi:
		_trail_mi.queue_free()
	_trail_pts.clear()
	_trail_fade = 1.0
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mi = MeshInstance3D.new()
	_trail_mi.material_override = _trail_mat
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(_trail_mi)

func _update_trail(dt: float) -> void:
	if not _trail_mi:
		return
	if drifting and f_speed > 8.0:
		var f := fwd()
		var side := Vector3(-f.z, 0.0, f.x)
		var rear := global_position - f * 1.35 + Vector3(0, 0.04, 0)
		_trail_pts.append([rear - side * 0.80, rear + side * 0.80])
		if _trail_pts.size() > TRAIL_MAX:
			_trail_pts.pop_front()
		_trail_fade = 0.0
		_rebuild_trail()
	else:
		if _trail_fade < 1.0:
			_trail_fade = minf(1.0, _trail_fade + dt * 0.25)
			_trail_mi.transparency = _trail_fade

func _rebuild_trail() -> void:
	var n := _trail_pts.size()
	if n < 2:
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in range(n):
		var pair: Array = _trail_pts[i]
		var l: Vector3 = pair[0]
		var r: Vector3 = pair[1]
		verts.append(l)
		verts.append(r)
		# older segments fade out
		var a := 0.75 * float(i) / float(n)
		cols.append(Color(0.02, 0.02, 0.025, a))
		cols.append(Color(0.02, 0.02, 0.025, a))
		if i > 0:
			var b := (i - 1) * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_trail_mi.mesh = mesh
	_trail_mi.transparency = 0.0

func _build_ltrail() -> void:
	# Tron-style vertical light ribbons at the taillights while drifting
	if _ltrail_mi:
		_ltrail_mi.queue_free()
	_ltrail_pts.clear()
	_ltrail_mat = StandardMaterial3D.new()
	_ltrail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ltrail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ltrail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ltrail_mat.vertex_color_use_as_albedo = true
	_ltrail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ltrail_mi = MeshInstance3D.new()
	_ltrail_mi.material_override = _ltrail_mat
	_ltrail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(_ltrail_mi)

func _update_ltrail(dt: float) -> void:
	if not _ltrail_mi:
		return
	if drifting and f_speed > 10.0:
		var f := fwd()
		var side := Vector3(-f.z, 0.0, f.x)
		var rear := global_position - f * 1.55 + Vector3(0, 0.72, 0)
		_ltrail_pts.append([rear - side * 0.55, rear + side * 0.55])
		if _ltrail_pts.size() > LTRAIL_MAX:
			_ltrail_pts.pop_front()
		_rebuild_ltrail()
	elif _ltrail_pts.size() > 0:
		_ltrail_pts.pop_front()
		_rebuild_ltrail()

func _rebuild_ltrail() -> void:
	var n := _ltrail_pts.size()
	if n < 2:
		_ltrail_mi.mesh = null
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var up := Vector3(0, 0.55, 0)
	for i in range(n):
		var pair: Array = _ltrail_pts[i]
		var l: Vector3 = pair[0]
		var r: Vector3 = pair[1]
		verts.append(l)
		verts.append(l + up)
		verts.append(r)
		verts.append(r + up)
		var a := 0.9 * float(i) / float(n)
		var c := Color(glow_color.r, glow_color.g, glow_color.b, a)
		cols.append(c)
		cols.append(c)
		cols.append(c)
		cols.append(c)
		if i > 0:
			var b := (i - 1) * 4
			idx.append_array([b, b + 1, b + 4, b + 1, b + 5, b + 4])
			idx.append_array([b + 2, b + 3, b + 6, b + 3, b + 7, b + 6])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_ltrail_mi.mesh = mesh

func _build_underglow() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var gc := glow_color
	grad.colors = PackedColorArray([Color(gc.r, gc.g, gc.b, 0.55), Color(gc.r, gc.g, gc.b, 0.0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 64
	gtex.height = 64
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = gtex
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 5.6)
	quad.mesh = qm
	quad.material_override = mat
	quad.rotation.x = -PI / 2.0
	quad.position = Vector3(0, 0.10, 0)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)  # child of car (not _body) so it stays flat
