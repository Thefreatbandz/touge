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
	var asphalt := Color(0.055, 0.06, 0.075)
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

	# mountain silhouettes
	var mtn_mesh := BoxMesh.new()
	mtn_mesh.size = Vector3.ONE
	var mtns: Array[Transform3D] = []
	for k in range(48):
		var i := rng.randi_range(0, COUNT - 1)
		var sgn := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := sgn * rng.randf_range(120.0, 320.0)
		var mp := points[i] + sides[i] * lat
		var sc := Vector3(rng.randf_range(60, 150), rng.randf_range(28, 80), rng.randf_range(40, 90))
		var basis := Basis().scaled(sc).rotated(Vector3.UP, rng.randf_range(0, TAU))
		mtns.append(Transform3D(basis, mp + Vector3(0, sc.y * 0.28, 0)))
	var mtn_mat := StandardMaterial3D.new()
	mtn_mat.albedo_color = Color(0.030, 0.042, 0.062)
	mtn_mat.roughness = 1.0
	_multimesh_box(self, mtn_mesh, mtn_mat, mtns)

	# trees (dark cones)
	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 2.6
	tree_mesh.height = 8.0
	var trees: Array[Transform3D] = []
	for k in range(380):
		var i := rng.randi_range(0, COUNT - 1)
		var sgn := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := sgn * rng.randf_range(11.0, 90.0)
		var tp := points[i] + sides[i] * lat
		var sc := rng.randf_range(0.7, 1.5)
		trees.append(Transform3D(Basis().scaled(Vector3(sc, sc, sc)), tp + Vector3(0, 4.0 * sc, 0)))
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
