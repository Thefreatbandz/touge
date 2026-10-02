extends CanvasLayer
## Race HUD: touch pedals + steering, timer, drift score, countdown, results.

signal start_pressed
signal restart_pressed

var t_steer_l := false
var t_steer_r := false
var t_gas := false
var t_brake := false
var t_hb := false

var _time_l: Label
var _drift_l: Label
var _speed_l: Label
var _prog: ProgressBar
var _center_l: Label
var _title_panel: Control
var _result_panel: Control
var _result_l: Label
var _hint_l: Label

func _ready() -> void:
	layer = 10
	_build()

func touch_steer() -> float:
	var s := 0.0
	if t_steer_l:
		s += 1.0
	if t_steer_r:
		s -= 1.0
	return s

func _mk_label(text: String, size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	l.horizontal_alignment = align
	return l

func _mk_button(text: String, pos: Vector2, size: Vector2, font := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.22, 0.55)
	sb.border_color = Color(0.5, 0.7, 1.0, 0.7)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(0.25, 0.45, 0.80, 0.75)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(b)
	return b

func _build() -> void:
	# top bar
	_time_l = _mk_label("0:00.0", 34, Vector2(24, 14))
	add_child(_time_l)
	_drift_l = _mk_label("DRIFT 0", 34, Vector2(1280 / 2 - 160, 14), HORIZONTAL_ALIGNMENT_CENTER)
	_drift_l.custom_minimum_size = Vector2(320, 44)
	add_child(_drift_l)
	_speed_l = _mk_label("0", 64, Vector2(1280 - 260, 8), HORIZONTAL_ALIGNMENT_RIGHT)
	_speed_l.custom_minimum_size = Vector2(160, 80)
	add_child(_speed_l)
	var unit := _mk_label("km/h", 22, Vector2(1280 - 96, 52))
	unit.modulate = Color(1, 1, 1, 0.6)
	add_child(unit)
	# progress bar
	_prog = ProgressBar.new()
	_prog.min_value = 0
	_prog.max_value = 1000
	_prog.position = Vector2(1280 / 2 - 260, 66)
	_prog.custom_minimum_size = Vector2(520, 14)
	_prog.size = Vector2(520, 14)
	_prog.show_percentage = false
	add_child(_prog)
	# steering (bottom-left)
	var bl := _mk_button("◀", Vector2(36, 720 - 190), Vector2(150, 150), 64)
	var br := _mk_button("▶", Vector2(200, 720 - 190), Vector2(150, 150), 64)
	bl.button_down.connect(func(): t_steer_l = true)
	bl.button_up.connect(func(): t_steer_l = false)
	br.button_down.connect(func(): t_steer_r = true)
	br.button_up.connect(func(): t_steer_r = false)
	# pedals (bottom-right)
	var gas := _mk_button("GAS", Vector2(1280 - 186, 720 - 250), Vector2(150, 210), 40)
	var brake := _mk_button("BRK", Vector2(1280 - 350, 720 - 190), Vector2(150, 150), 40)
	var hb := _mk_button("HB", Vector2(1280 - 350, 720 - 330), Vector2(150, 120), 40)
	gas.button_down.connect(func(): t_gas = true)
	gas.button_up.connect(func(): t_gas = false)
	brake.button_down.connect(func(): t_brake = true)
	brake.button_up.connect(func(): t_brake = false)
	hb.button_down.connect(func(): t_hb = true)
	hb.button_up.connect(func(): t_hb = false)
	# center label (countdown / messages)
	_center_l = _mk_label("", 120, Vector2(0, 220), HORIZONTAL_ALIGNMENT_CENTER)
	_center_l.custom_minimum_size = Vector2(1280, 200)
	_center_l.visible = false
	add_child(_center_l)
	# desktop hint
	_hint_l = _mk_label("Arrows/WASD drive · SPACE handbrake", 20, Vector2(0, 690), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_l.custom_minimum_size = Vector2(1280, 28)
	_hint_l.modulate = Color(1, 1, 1, 0.45)
	add_child(_hint_l)
	# title overlay
	_title_panel = _mk_dim()
	var tt := _mk_label("TOUGE", 110, Vector2(0, 150), HORIZONTAL_ALIGNMENT_CENTER)
	tt.custom_minimum_size = Vector2(1280, 150)
	tt.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	_title_panel.add_child(tt)
	var ts := _mk_label("night pass time attack · own the drift", 30, Vector2(0, 300), HORIZONTAL_ALIGNMENT_CENTER)
	ts.custom_minimum_size = Vector2(1280, 50)
	ts.modulate = Color(1, 1, 1, 0.75)
	_title_panel.add_child(ts)
	var go_b := Button.new()
	go_b.text = "TAP TO RACE"
	go_b.position = Vector2(1280 / 2 - 170, 430)
	go_b.custom_minimum_size = Vector2(340, 100)
	go_b.size = Vector2(340, 100)
	go_b.add_theme_font_size_override("font_size", 44)
	go_b.pressed.connect(func(): emit_signal("start_pressed"))
	_title_panel.add_child(go_b)
	add_child(_title_panel)
	# results panel (hidden)
	_result_panel = _mk_dim()
	_result_l = _mk_label("", 44, Vector2(0, 180), HORIZONTAL_ALIGNMENT_CENTER)
	_result_l.custom_minimum_size = Vector2(1280, 300)
	_result_l.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_result_panel.add_child(_result_l)
	var re := Button.new()
	re.text = "RUN IT BACK"
	re.position = Vector2(1280 / 2 - 170, 500)
	re.custom_minimum_size = Vector2(340, 90)
	re.size = Vector2(340, 90)
	re.add_theme_font_size_override("font_size", 38)
	re.pressed.connect(func(): emit_signal("restart_pressed"))
	_result_panel.add_child(re)
	_result_panel.visible = false
	add_child(_result_panel)

func _mk_dim() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.03, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	return c

func show_title() -> void:
	_title_panel.visible = true
	_result_panel.visible = false

func hide_title() -> void:
	_title_panel.visible = false

func set_center(t: String) -> void:
	_center_l.visible = t != ""
	_center_l.text = t

func set_hud(time_s: float, drift: float, kmh: float, prog: float) -> void:
	_time_l.text = _fmt_time(time_s)
	_drift_l.text = "DRIFT %d" % int(drift)
	_speed_l.text = "%d" % int(kmh)
	_prog.value = prog * 1000.0

func show_results(time_s: float, drift: float, best: float, new_best: bool) -> void:
	var nb := "\nNEW BEST!" if new_best else ""
	_result_l.text = "FINISH!\nTime  %s\nDrift  %d pts\nBest  %s%s" % [
		_fmt_time(time_s), int(drift), _fmt_time(best), nb]
	_result_panel.visible = true

func hide_results() -> void:
	_result_panel.visible = false

func _fmt_time(s: float) -> String:
	var m := int(s) / 60
	var sec := s - m * 60
	return "%d:%04.1f" % [m, sec]
