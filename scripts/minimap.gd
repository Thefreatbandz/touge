extends Control
## PS1-style race minimap: track outline + player/rival dots.

var _pts := PackedVector3Array()
var _p1 := Vector3.ZERO
var _p2 := Vector3.ZERO
var _has_p2 := false
var _min := Vector2.ZERO
var _span := Vector2.ONE

func set_track(pts: PackedVector3Array) -> void:
	_pts = pts
	if pts.is_empty():
		return
	var mn := Vector2(pts[0].x, pts[0].z)
	var mx := mn
	for p in pts:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.z)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.z)
	_min = mn
	_span = (mx - mn) + Vector2(20.0, 20.0)
	queue_redraw()

func set_cars(p1: Vector3, p2: Vector3, has_p2: bool) -> void:
	_p1 = p1
	_p2 = p2
	_has_p2 = has_p2
	queue_redraw()

func _to_map(p: Vector3) -> Vector2:
	var pad := 10.0
	var avail := size - Vector2(pad * 2.0, pad * 2.0)
	var sc := minf(avail.x / _span.x, avail.y / _span.y)
	var off := (size - _span * sc) * 0.5
	return off + (Vector2(p.x, p.z) - _min + Vector2(10.0, 10.0)) * sc

func _draw() -> void:
	# panel
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.62))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.7, 1.0, 0.5), false, 2.0)
	if _pts.size() < 2:
		return
	var line := PackedVector2Array()
	var step := maxi(1, _pts.size() / 120)
	var k := 0
	while k < _pts.size():
		line.append(_to_map(_pts[k]))
		k += step
	line.append(_to_map(_pts[0]))
	draw_polyline(line, Color(0.75, 0.82, 0.95, 0.85), 2.0)
	if _has_p2:
		draw_circle(_to_map(_p2), 5.0, Color(1.0, 0.15, 0.12))
		draw_circle(_to_map(_p2), 7.5, Color(1.0, 0.15, 0.12, 0.35))
	draw_circle(_to_map(_p1), 5.0, Color(0.35, 1.0, 0.6))
	draw_circle(_to_map(_p1), 7.5, Color(0.35, 1.0, 0.6, 0.35))
