extends Node3D
## Procedural night mountain pass: winding road ribbon, guardrails, streetlights,
## trees, mountain silhouettes, start/finish gates. Also answers collision queries.

const STEP := 4.0
const COUNT := 380          # ~1520 m point-to-point
const ROAD_HALF := 5.0
const CURVE_K := 0.04

var points: PackedVector3Array
var tangents: PackedVector3Array
var sides: PackedVector3Array      # right vector at each point
var yaws: PackedFloat32Array       # heading yaw matching car.gd convention
var start_idx := 8
var finish_idx := COUNT - 12

var _mat_flat: StandardMaterial3D
var _mat_emit: StandardMaterial3D
var _mat_gray: StandardMaterial3D

func generate(seed: int) -> void:
	_mat_flat = StandardMaterial3D.new()
	_mat_flat.vertex_color_use_as_albedo = true
	_mat_flat.roughness = 1.0
	_mat_flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_emit = StandardMaterial3D.new()
	_mat_emit.vertex_color_use_as_albedo = true
	_mat_emit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_emit.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_gray = StandardMaterial3D.new()
	_mat_gray.albedo_color = Color(0.32, 0.35, 0.39)
	_mat_gray.roughness = 0.9
	var rng := RandomNumberGenerator.new()
	var ok := false
	var attempt := 0
	while not ok and attempt < 10:
		rng.seed = seed + attempt * 7919
		_layout(rng)
		ok = _check_clearance()
		attempt += 1
	_build_road(rng)
	_build_scenery(rng)
	_build_gates()

func _layout(rng: RandomNumberGenerator) -> void:
	points = PackedVector3Array()
	tangents = PackedVector3Array()
	sides = PackedVector3Array()
	yaws = PackedFloat32Array()
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var p3 := rng.randf_range(0.0, TAU)
	var pos := Vector3.ZERO
	var yaw := 0.0
	for i in range(COUNT):
		var t := float(i) * STEP
		var curve := 0.62 * sin(t * 0.0060 + p1) \
			+ 0.38 * sin(t * 0.0137 + p2) \
			+ 0.22 * sin(t * 0.0311 + p3)
		yaw += curve * STEP * CURVE_K
		# hard heading clamp: the pass meanders and throws hairpins (up to
		# ~115 deg) but can never wind into a loop; it always traverses forward.
		yaw = clampf(yaw, -2.0, 2.0)
		var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
		pos += dir * STEP
		points.append(pos)
		tangents.append(dir)
		var side := dir.cross(Vector3.UP).normalized()  # right of travel
		sides.append(side)
		yaws.append(yaw)

func _check_clearance() -> bool:
	# no part of the road may come near a non-adjacent part (no overlaps/loops)
	for i in range(COUNT):
		var pi := points[i]
		for j in range(i + 30, COUNT):
			var d2 := pi.distance_squared_to(points[j])
			if d2 < 48.0 * 48.0:
				return false
	# heading must never wind into a loop
	return true

# --- mesh helpers -----------------------------------------------------------

var _v: PackedVector3Array
var _n: PackedVector3Array
var _c: PackedColorArray

func _begin() -> void:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, nrm: Vector3) -> void:
	# a,b at near edge; c,d at far edge. Winding irrelevant (cull disabled).
	_v.append_array([a, b, c, b, d, c])
	for i in range(6):
		_n.append(nrm)
		_c.append(col)

func _finish(parent: Node3D, mat: Material) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _multimesh_box(parent: Node3D, mesh: Mesh, mat: Material, transforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)

# --- road -------------------------------------------------------------------

func _build_road(rng: RandomNumberGenerator) -> void:
	_begin()
	var up := Vector3.UP
	var asphalt := Color(0.085, 0.09, 0.105)
	for i in range(COUNT - 1):
		var p := points[i]
		var q := points[i + 1]
		var s := sides[i]
		var shade := rng.randf_range(0.9, 1.1)
		var col := Color(asphalt.r * shade, asphalt.g * shade, asphalt.b * shade)
		_quad(p - s * ROAD_HALF, p + s * ROAD_HALF,
			q - s * ROAD_HALF, q + s * ROAD_HALF, col, up)
		# edge lines
		var e := 4.45
		var w := 0.28
		var lc := Color(0.42, 0.44, 0.46)
		_quad(p - s * (e + w) + up * 0.02, p - s * e + up * 0.02,
			q - s * (e + w) + up * 0.02, q - s * e + up * 0.02, lc, up)
		_quad(p + s * e + up * 0.02, p + s * (e + w) + up * 0.02,
			q + s * e + up * 0.02, q + s * (e + w) + up * 0.02, lc, up)
		# center dashes every 3rd segment
		if i % 3 == 0:
			var dc := Color(0.5, 0.44, 0.22)
			_quad(p - s * 0.12 + up * 0.02, p + s * 0.12 + up * 0.02,
				q - s * 0.12 + up * 0.02, q + s * 0.12 + up * 0.02, dc, up)
		# guardrail bands (vertical ribbons, both sides)
		var g := ROAD_HALF + 0.45
		var rc := Color(0.30, 0.33, 0.37)
		var nL := -sides[i]
		_quad(p + s * g + up * 0.45, p + s * g + up * 0.78,
			q + s * g + up * 0.45, q + s * g + up * 0.78, rc, nL)
		_quad(p - s * g + up * 0.78, p - s * g + up * 0.45,
			q - s * g + up * 0.78, q - s * g + up * 0.45, rc, sides[i])
	_finish(self, _mat_flat)

	# guardrail posts (instanced)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 0.8, 0.16)
	var posts: Array[Transform3D] = []
	var refl: Array[Transform3D] = []
	for i in range(0, COUNT - 1, 2):
		for sgn: float in [-1.0, 1.0]:
			var bp := points[i] + sides[i] * (sgn * (ROAD_HALF + 0.45))
			posts.append(Transform3D(Basis(), bp + Vector3(0, 0.4, 0)))
			if i % 8 == 0:
				refl.append(Transform3D(Basis(), bp + Vector3(0, 0.72, 0)))
	_multimesh_box(self, post_mesh, _mat_gray, posts)
	var refl_mesh := BoxMesh.new()
	refl_mesh.size = Vector3(0.12, 0.14, 0.07)
	_multimesh_box(self, refl_mesh, _mat_emit, refl)

# --- scenery ----------------------------------------------------------------

func _build_scenery(rng: RandomNumberGenerator) -> void:
	# ground with subtle color noise
	_begin()
	var mid := points[COUNT / 2]
	var gs := 1500.0
	var div := 24
	var cell := gs / div
	for gx in range(div):
		for gz in range(div):
			var x0 := mid.x - gs / 2.0 + gx * cell
			var z0 := mid.z - gs / 2.0 + gz * cell
			var v := rng.randf_range(0.8, 1.25)
			var col := Color(0.020 * v, 0.030 * v, 0.038 * v)
			_quad(Vector3(x0, -0.4, z0), Vector3(x0 + cell, -0.4, z0),
				Vector3(x0, -0.4, z0 + cell), Vector3(x0 + cell, -0.4, z0 + cell),
				col, Vector3.UP)
	_finish(self, _mat_flat)

	# --- retro PS1 city: chunky blocks with lit windows, clear of the road ---
	_build_city(rng)

	# trees (dark cones) — kept clear of the road even where it bends back
	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 2.6
	tree_mesh.height = 8.0
	var trees: Array[Transform3D] = []
	var placed := 0
	var guard := 0
	while placed < 380 and guard < 4000:
		guard += 1
		var i := rng.randi_range(0, COUNT - 1)
		var sgn := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := sgn * rng.randf_range(11.0, 90.0)
		var tp := points[i] + sides[i] * lat
		# reject if too close to ANY part of the road (curves can double back)
		var clear := true
		for j in range(COUNT):
			var dx := tp.x - points[j].x
			var dz := tp.z - points[j].z
			if dx * dx + dz * dz < 9.0 * 9.0:
				clear = false
				break
		if not clear:
			continue
		var sc := rng.randf_range(0.7, 1.5)
		trees.append(Transform3D(Basis().scaled(Vector3(sc, sc, sc)), tp + Vector3(0, 4.0 * sc, 0)))
		placed += 1
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.020, 0.055, 0.032)
	tree_mat.roughness = 1.0
	_multimesh_box(self, tree_mesh, tree_mat, trees)

	# streetlights: poles + emissive lamp heads, alternating sides
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.22, 7.0, 0.22)
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(1.1, 0.22, 0.5)
	var poles: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var sgn := 1.0
	for i in range(10, COUNT - 10, 17):
		sgn = -sgn
		var bp := points[i] + sides[i] * (sgn * 7.6)
		poles.append(Transform3D(Basis(), bp + Vector3(0, 3.5, 0)))
		var lp := points[i] + sides[i] * (sgn * 6.6)
		lamps.append(Transform3D(Basis(), lp + Vector3(0, 6.9, 0)))
	_multimesh_box(self, pole_mesh, _mat_gray, poles)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1.0, 0.85, 0.55)
	_multimesh_box(self, lamp_mesh, lamp_mat, lamps)

	_build_billboards(rng)
	_build_poles_wires(rng)
	_build_rail_markers()
	_build_sky_extras(rng)

func _build_gates() -> void:
	for g in [[start_idx, Color(0.2, 1.0, 0.9)], [finish_idx, Color(1.0, 0.75, 0.2)]]:
		var i: int = g[0]
		var tint: Color = g[1]
		var gate := Node3D.new()
		add_child(gate)
		_begin()
		var s := sides[i]
		var p := points[i]
		var post_c := Color(0.16, 0.17, 0.20)
		for sgn: float in [-1.0, 1.0]:
			var bp := p + s * (sgn * 6.4)
			_quad(bp + Vector3(-0.3, 0, -0.3), bp + Vector3(0.3, 0, -0.3),
				bp + Vector3(-0.3, 7.4, -0.3), bp + Vector3(0.3, 7.4, -0.3), post_c, s)
		# beam across
		var b0 := p - s * 6.7 + Vector3(0, 7.0, 0)
		var b1 := p + s * 6.7 + Vector3(0, 7.0, 0)
		_quad(b0, b0 + Vector3(0, 1.1, 0), b1, b1 + Vector3(0, 1.1, 0), post_c, tangents[i])
		_finish(gate, _mat_flat)
		# glowing banner
		_begin()
		var q0 := p - s * 5.9 + Vector3(0, 5.2, 0)
		var q1 := p + s * 5.9 + Vector3(0, 5.2, 0)
		_quad(q0, q1, q0 + Vector3(0, 1.4, 0), q1 + Vector3(0, 1.4, 0), tint, tangents[i])
		_finish(gate, _mat_emit)

func _rot_y(v: Vector3, yaw: float) -> Vector3:
	var sy := sin(yaw)
	var cy := cos(yaw)
	return Vector3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy)

func _box_at(c: Vector3, size: Vector3, yaw: float, col: Color) -> void:
	# rotated box into the active _v/_n/_c arrays (cull off, winding is free)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for syy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(c + _rot_y(Vector3(sx * hx, syy * hy, sz * hz), yaw))
	var faces := [[0, 1, 4, 5], [2, 3, 6, 7], [0, 1, 2, 3], [4, 5, 6, 7], [0, 2, 4, 6], [1, 3, 5, 7]]
	var norms := [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for fi in range(6):
		var f: Array = faces[fi]
		var rn := _rot_y(norms[fi], yaw)
		_quad(corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], col, rn)

func _build_city(rng: RandomNumberGenerator) -> void:
	# placement: [pos, radius, w, h, d, yaw]
	var placed: Array = []
	var guard := 0
	var body_cols := [Color(0.10, 0.12, 0.17), Color(0.13, 0.11, 0.10),
		Color(0.09, 0.11, 0.15), Color(0.12, 0.13, 0.14), Color(0.11, 0.09, 0.13)]
	while placed.size() < 55 and guard < 3000:
		guard += 1
		var i := rng.randi_range(0, COUNT - 1)
		var sgn := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := sgn * rng.randf_range(24.0, 90.0)
		var bp := points[i] + sides[i] * lat
		var w := rng.randf_range(10.0, 22.0)
		var d := rng.randf_range(10.0, 22.0)
		var h := rng.randf_range(12.0, 48.0)
		var rad := maxf(w, d) * 0.5 + 13.0
		var ok := true
		for j in range(0, COUNT, 2):
			var dx := bp.x - points[j].x
			var dz := bp.z - points[j].z
			if dx * dx + dz * dz < rad * rad:
				ok = false
				break
		if ok:
			for pb in placed:
				var pc: Vector3 = pb[0]
				var pr: float = pb[1]
				var ddx := bp.x - pc.x
				var ddz := bp.z - pc.z
				if ddx * ddx + ddz * ddz < (rad + pr) * (rad + pr):
					ok = false
					break
		if not ok:
			continue
		placed.append([bp, rad, w, h, d, float(yaws[i])])
	# bodies (flat PS1 colors, one mesh)
	_begin()
	for pb in placed:
		var bp: Vector3 = pb[0]
		var w: float = pb[2]
		var h: float = pb[3]
		var d: float = pb[4]
		var yaw: float = pb[5]
		var col: Color = body_cols[rng.randi_range(0, body_cols.size() - 1)]
		var shade := rng.randf_range(0.85, 1.15)
		_box_at(bp + Vector3(0, h * 0.5, 0), Vector3(w, h, d), yaw,
			Color(col.r * shade, col.g * shade, col.b * shade))
	_finish(self, _mat_flat)
	# windows + rooftop beacons (emissive, one mesh)
	_begin()
	var warm := Color(1.0, 0.72, 0.32)
	var cool := Color(0.62, 0.80, 1.0)
	for pb in placed:
		var bp: Vector3 = pb[0]
		var w: float = pb[2]
		var h: float = pb[3]
		var d: float = pb[4]
		var yaw: float = pb[5]
		# 4 vertical faces: [outward normal, u axis, face width, half extent]
		var rx := _rot_y(Vector3.RIGHT, yaw)
		var fz := _rot_y(Vector3.FORWARD, yaw)
		var bk := _rot_y(Vector3.BACK, yaw)
		var face_defs := [
			[rx, fz, d, w * 0.5],
			[-rx, fz, d, w * 0.5],
			[bk, rx, w, d * 0.5],
			[-bk, rx, w, d * 0.5],
		]
		for fd in face_defs:
			var n: Vector3 = fd[0]
			var u: Vector3 = fd[1]
			var fw: float = fd[2]
			var he: float = fd[3]
			var fcenter := bp + n * he
			var rows := int((h - 5.0) / 4.0)
			var cols := int((fw - 3.0) / 3.0)
			for r in range(rows):
				var wy := 3.5 + r * 4.0
				for cc in range(cols):
					var wx := -fw * 0.5 + 2.0 + cc * 3.0
					var roll := rng.randf()
					if roll > 0.92:
						continue  # dark window
					var wc := warm if roll < 0.68 else cool
					var wp := fcenter + u * wx + Vector3(0, wy, 0) + n * 0.07
					var hu := u * 0.75
					var hv := Vector3(0, 1.1, 0)
					_quad(wp - hu - hv, wp + hu - hv, wp - hu + hv, wp + hu + hv, wc, n)
		if h > 30.0:
			_box_at(bp + Vector3(0, h + 0.4, 0), Vector3(0.9, 0.9, 0.9), 0.0, Color(1.0, 0.12, 0.10))
	_finish(self, _mat_emit)

func _wire(p1: Vector3, p2: Vector3, thick: float, col: Color) -> void:
	# two-segment sagging wire into the active arrays
	var mid := (p1 + p2) * 0.5
	mid.y -= 0.9
	for seg in [[p1, mid], [mid, p2]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var d := b - a
		var yaw := atan2(d.x, d.z)
		var length := Vector3(d.x, 0.0, d.z).length()
		_box_at((a + b) * 0.5, Vector3(thick, thick, length), yaw, col)

func _build_billboards(rng: RandomNumberGenerator) -> void:
	var texts := ["TOUGE", "DRIFT", "APEX", "REDLINE", "MIDNIGHT", "NITRO", "TURBO", "GP 90"]
	var cols := [Color(0.25, 1.0, 1.0), Color(1.0, 0.3, 0.85), Color(1.0, 0.85, 0.25),
		Color(1.0, 0.5, 0.15), Color(0.5, 1.0, 0.45)]
	_begin()
	var n := 0
	var guard := 0
	while n < 9 and guard < 600:
		guard += 1
		var i := rng.randi_range(20, COUNT - 21)
		var sgn := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := sgn * rng.randf_range(13.0, 18.0)
		var bp := points[i] + sides[i] * lat
		var ok := true
		for j in range(maxi(0, i - 10), mini(COUNT, i + 11)):
			var dx := bp.x - points[j].x
			var dz := bp.z - points[j].z
			if dx * dx + dz * dz < 64.0:
				ok = false
				break
		if not ok:
			continue
		n += 1
		var tangent := (points[i + 1] - points[i - 1]).normalized()
		var to_road := -sides[i] * sgn
		var pc := bp + Vector3(0, 7.6, 0)
		var neon: Color = cols[rng.randi_range(0, cols.size() - 1)]
		var up := Vector3(0, 1, 0)
		var hw := 4.6
		var hh := 2.3
		# dark panel backing
		_quad(pc - tangent * hw - up * hh, pc + tangent * hw - up * hh,
			pc - tangent * hw + up * hh, pc + tangent * hw + up * hh,
			Color(0.015, 0.02, 0.05), to_road)
		# neon border
		var bt := 0.18
		_quad(pc + up * hh - tangent * (hw + bt), pc + up * hh + tangent * (hw + bt),
			pc + up * (hh + bt) - tangent * (hw + bt), pc + up * (hh + bt) + tangent * (hw + bt), neon, to_road)
		_quad(pc - up * (hh + bt) - tangent * (hw + bt), pc - up * (hh + bt) + tangent * (hw + bt),
			pc - up * hh - tangent * (hw + bt), pc - up * hh + tangent * (hw + bt), neon, to_road)
		_quad(pc - tangent * (hw + bt) - up * hh, pc - tangent * hw - up * hh,
			pc - tangent * (hw + bt) + up * hh, pc - tangent * hw + up * hh, neon, to_road)
		_quad(pc + tangent * hw - up * hh, pc + tangent * (hw + bt) - up * hh,
			pc + tangent * hw + up * hh, pc + tangent * (hw + bt) + up * hh, neon, to_road)
		# support poles (dark, in the unshaded pass they stay dark)
		for ps in [-3.2, 3.2]:
			_box_at(bp + tangent * ps + Vector3(0, 2.6, 0), Vector3(0.35, 5.2, 0.35), 0.0,
				Color(0.05, 0.05, 0.07))
		_finish(self, _mat_emit)
		# floating text
		var lab := Label3D.new()
		lab.text = texts[rng.randi_range(0, texts.size() - 1)]
		lab.font_size = 96
		lab.pixel_size = 0.018
		lab.modulate = neon
		lab.outline_size = 16
		lab.outline_modulate = Color(0, 0, 0, 1)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.shaded = false
		lab.position = pc + to_road * 0.4
		add_child(lab)

func _build_poles_wires(rng: RandomNumberGenerator) -> void:
	_begin()
	var tops_l: Array[Vector3] = []
	var tops_r: Array[Vector3] = []
	var k := 8
	while k < COUNT - 8:
		for sgn: float in [-1.0, 1.0]:
			var pp := points[k] + sides[k] * (sgn * 8.2)
			var ok := true
			for j in range(maxi(0, k - 6), mini(COUNT, k + 7)):
				var dx := pp.x - points[j].x
				var dz := pp.z - points[j].z
				if dx * dx + dz * dz < 49.0:
					ok = false
					break
			if not ok:
				continue
			_box_at(pp + Vector3(0, 4.5, 0), Vector3(0.3, 9.0, 0.3), 0.0, Color(0.075, 0.075, 0.09))
			var top := pp + Vector3(0, 8.9, 0)
			if sgn < 0.0:
				tops_l.append(top)
			else:
				tops_r.append(top)
		k += 13
	_finish(self, _mat_flat)
	_begin()
	for arr in [tops_l, tops_r]:
		for wi in range(arr.size() - 1):
			_wire(arr[wi], arr[wi + 1], 0.08, Color(0.02, 0.02, 0.03))
	_finish(self, _mat_flat)

func _build_rail_markers() -> void:
	_begin()
	var up := Vector3(0, 1, 0)
	var k := 0
	while k < COUNT:
		for sgn: float in [-1.0, 1.0]:
			var rp := points[k] + sides[k] * (sgn * 5.45) + Vector3(0, 0.72, 0)
			var nrm := -sides[k] * sgn
			var rt := nrm.cross(up).normalized()
			var col := Color(1.0, 0.18, 0.12) if sgn < 0.0 else Color(0.95, 0.95, 1.0)
			var s := 0.16
			_quad(rp - rt * s - up * s, rp + rt * s - up * s,
				rp - rt * s + up * s, rp + rt * s + up * s, col, nrm)
		k += 3
	_finish(self, _mat_emit)

func _build_sky_extras(rng: RandomNumberGenerator) -> void:
	var c := (points[0] + points[COUNT / 2]) * 0.5
	# chunky low-poly moon, fog-exempt so it stays crisp
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 20.0
	moon_mesh.height = 40.0
	moon_mesh.radial_segments = 8
	moon_mesh.rings = 4
	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.88, 0.92, 1.0)
	moon_mat.disable_fog = true
	var moon := MeshInstance3D.new()
	moon.mesh = moon_mesh
	moon.material_override = moon_mat
	moon.position = c + Vector3(280, 260, -340)
	add_child(moon)
	# stars: tiny emissive boxes on a dome, fog-exempt
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(1.6, 1.6, 1.6)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.85, 0.9, 1.0)
	star_mat.disable_fog = true
	var xf: Array[Transform3D] = []
	for s in range(140):
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(420.0, 620.0)
		var h := rng.randf_range(170.0, 400.0)
		xf.append(Transform3D(Basis(), c + Vector3(cos(ang) * rad, h, sin(ang) * rad)))
	_multimesh_box(self, star_mesh, star_mat, xf)

# --- queries ----------------------------------------------------------------

func query(pos: Vector3, hint: int) -> Vector3:
	# x = nearest point index, y = lateral offset (+ = right of center)
	var best_i := hint
	var best_d := INF
	var lo := maxi(0, hint - 14)
	var hi := mini(points.size() - 1, hint + 14)
	for i in range(lo, hi + 1):
		var d := pos.distance_squared_to(points[i])
		if d < best_d:
			best_d = d
			best_i = i
	var lat := (pos - points[best_i]).dot(sides[best_i])
	return Vector3(best_i, lat, 0.0)

func start_pose() -> Array:
	return [points[start_idx], yaws[start_idx], start_idx]

func progress_of(idx: int) -> float:
	return clampf(float(idx - start_idx) / float(finish_idx - start_idx), 0.0, 1.0)
