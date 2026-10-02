extends Node
## Debug: render track centerline + driven path top-down to a PNG.

var _main = null
var _frame := 0
var _path: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	add_child(_main)
	_main._on_start()
	_main._state = 2
	_main._car.active = true
	_main._test_steer_on = true

func _process(_dt: float) -> void:
	_frame += 1
	var car = _main._car
	var track = _main._track
	_path.append(Vector2(car.global_position.x, car.global_position.z))
	# same driver as drive_test
	var la_steps := clampi(int(5.0 + car.f_speed * 0.55), 6, 20)
	var ahead := mini(car._seg + la_steps, track.points.size() - 1)
	var to_t: Vector3 = track.points[ahead] - car.global_position
	var dy := wrapf(atan2(-to_t.x, -to_t.z) - car.yaw, -PI, PI)
	var dy_max := absf(dy)
	for k in range(8, 30, 4):
		var ai := mini(car._seg + k, track.points.size() - 1)
		var tk: Vector3 = track.points[ai] - car.global_position
		dy_max = maxf(dy_max, absf(wrapf(atan2(-tk.x, -tk.z) - car.yaw, -PI, PI)))
	_main._test_steer = clampf(dy * 2.2, -1.0, 1.0)
	var hud = _main._hud
	hud.t_gas = dy_max < 2.4 and dy_max < 1.1
	hud.t_brake = dy_max > 0.7 and car.f_speed > 16.0
	if _frame == 4000:
		_render(track)
		print("MAP SAVED seg=", car._seg, " fspeed=", car.f_speed)

func _render(track) -> void:
	var pts: PackedVector3Array = track.points
	var minx := 1e9
	var maxx := -1e9
	var minz := 1e9
	var maxz := -1e9
	for p in pts:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z)
		maxz = maxf(maxz, p.z)
	var W := 1000
	var H := 1000
	var sc := minf(W / (maxx - minx + 40.0), H / (maxz - minz + 40.0))
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.02, 0.02, 0.04))
	var px := func(p: Vector3) -> Vector2i:
		return Vector2i(int((p.x - minx + 20) * sc), int((p.z - minz + 20) * sc))
	# rails area (road edges)
	for i in range(pts.size()):
		var c: Vector2i = px.call(pts[i])
		for r in range(3):
			for a in range(12):
				var o := Vector2i(int(cos(a / 12.0 * TAU) * r), int(sin(a / 12.0 * TAU) * r))
				var q: Vector2i = c + o
				if q.x >= 0 and q.y >= 0 and q.x < W and q.y < H:
					img.set_pixel(q.x, q.y, Color(0.35, 0.35, 0.4))
	# driven path (green)
	for v in _path:
		var q := Vector2i(int((v.x - minx + 20) * sc), int((v.y - minz + 20) * sc))
		if q.x >= 0 and q.y >= 0 and q.x < W and q.y < H:
			img.set_pixel(q.x, q.y, Color(0.1, 1.0, 0.2))
	# car (red cross)
	var cp: Vector3 = _main._car.global_position
	var cc: Vector2i = px.call(cp)
	for o in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]:
		var q: Vector2i = cc + o
		if q.x >= 0 and q.y >= 0 and q.x < W and q.y < H:
			img.set_pixel(q.x, q.y, Color(1, 0.1, 0.1))
	img.save_png("/tmp/touge_map.png")
