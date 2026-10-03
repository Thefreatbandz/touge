extends CanvasLayer
## Race HUD: touch pedals + steering, timer, drift score, minimap, rival gap, results.

signal start_pressed
signal restart_pressed
signal photo_pressed

const MinimapScript := preload("res://scripts/minimap.gd")

var t_steer_l := false
var t_steer_r := false
var t_gas := false
var t_brake := false
var t_hb := false
var t_nitro := false

func set_nitro(v: float) -> void:
	if _nitro_bar:
		_nitro_bar.value = v * 100.0

var _time_l: Label
var _drift_l: Label
var _speed_l: Label
var _gap_l: Label
var _pos_l: Label
var _map: MinimapScript
var _prog: ProgressBar
var _center_l: Label
var _title_panel: Control
var _result_panel: Control
var _result_l: Label
var _hint_l: Label
var _speed_lines: Array = []
var _nitro_btn: Button
var _nitro_bar: ProgressBar
var _photo_btn: Button
var _rain_btn: Button
var rain_on := false
signal rain_toggled(on: bool)

func _on_rain_toggle() -> void:
	rain_on = not rain_on
	_rain_btn.text = "RAIN: ON" if rain_on else "RAIN: OFF"
	emit_signal("rain_toggled", rain_on)

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

const FONT_DISPLAY := preload("res://assets/fonts/Orbitron.ttf")      # titles, countdown
const FONT_HUD := preload("res://assets/fonts/Rajdhani.ttf")          # HUD labels
const FONT_MONO := preload("res://assets/fonts/ShareTechMono.ttf")    # timers

func _mk_label(text: String, size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", FONT_HUD)
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
	b.focus_mode = Control.FOCUS_NONE  # never steal SPACE/ENTER from driving
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_font_override("font", FONT_HUD)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.85))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.10, 0.68)
	sb.border_color = Color(1.0, 0.62, 0.25, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(20)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(0.85, 0.45, 0.16, 0.88)
	sbp.border_color = Color(1.0, 0.80, 0.45, 1.0)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(b)
	return b

func _build() -> void:
	# speed lines (screen-edge streaks, alpha driven by speed; drawn first = behind UI)
	_speed_lines.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(12):
		var line := ColorRect.new()
		var left_side := i % 2 == 0
		var lx := rng.randf_range(8.0, 90.0) if left_side else rng.randf_range(1190.0, 1272.0)
		var ly := rng.randf_range(120.0, 640.0)
		var lh := rng.randf_range(60.0, 180.0)
		line.position = Vector2(lx, ly)
		line.size = Vector2(3, lh)
		line.color = Color(1, 1, 1, 0.0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		_speed_lines.append(line)
	# top HUD backdrop: gradient strip + amber accent line
	var strip := ColorRect.new()
	strip.color = Color(0.04, 0.025, 0.035, 0.62)
	strip.position = Vector2(0, 0)
	strip.size = Vector2(1280, 132)
	add_child(strip)
	var accent := ColorRect.new()
	accent.color = Color(1.0, 0.62, 0.25, 0.85)
	accent.position = Vector2(0, 130)
	accent.size = Vector2(1280, 3)
	add_child(accent)
	# top bar
	_time_l = _mk_label("0:00.0", 36, Vector2(28, 12))
	_time_l.add_theme_font_override("font", FONT_MONO)
	_time_l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	add_child(_time_l)
	var time_cap := _mk_label("TIME", 18, Vector2(28, 52))
	time_cap.add_theme_color_override("font_color", Color(1.0, 0.72, 0.40, 0.75))
	add_child(time_cap)
	_drift_l = _mk_label("DRIFT 0", 40, Vector2(1280 / 2 - 170, 10), HORIZONTAL_ALIGNMENT_CENTER)
	_drift_l.custom_minimum_size = Vector2(340, 52)
	_drift_l.add_theme_font_override("font", FONT_DISPLAY)
	_drift_l.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	add_child(_drift_l)
	# big speed readout (right)
	_speed_l = _mk_label("0", 92, Vector2(1280 - 280, 0), HORIZONTAL_ALIGNMENT_RIGHT)
	_speed_l.custom_minimum_size = Vector2(180, 100)
	_speed_l.add_theme_font_override("font", FONT_DISPLAY)
	_speed_l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	add_child(_speed_l)
	var unit := _mk_label("KM/H", 20, Vector2(1280 - 100, 74))
	unit.add_theme_color_override("font_color", Color(1.0, 0.72, 0.40, 0.8))
	add_child(unit)
	# progress bar (styled)
	_prog = ProgressBar.new()
	_prog.min_value = 0
	_prog.max_value = 1000
	_prog.position = Vector2(1280 / 2 - 260, 68)
	_prog.custom_minimum_size = Vector2(520, 12)
	_prog.size = Vector2(520, 12)
	_prog.show_percentage = false
	var prog_bg := StyleBoxFlat.new()
	prog_bg.bg_color = Color(0.10, 0.08, 0.10, 0.7)
	prog_bg.set_corner_radius_all(6)
	_prog.add_theme_stylebox_override("background", prog_bg)
	var prog_fill := StyleBoxFlat.new()
	prog_fill.bg_color = Color(1.0, 0.62, 0.25, 0.95)
	prog_fill.set_corner_radius_all(6)
	_prog.add_theme_stylebox_override("fill", prog_fill)
	add_child(_prog)
	# rival gap (under progress bar)
	_gap_l = _mk_label("", 26, Vector2(0, 88), HORIZONTAL_ALIGNMENT_CENTER)
	_gap_l.custom_minimum_size = Vector2(1280, 34)
	_gap_l.add_theme_font_override("font", FONT_MONO)
	add_child(_gap_l)
	# position badge: pill background + big text (top-right, under speed)
	var pos_pill := ColorRect.new()
	pos_pill.color = Color(0.08, 0.06, 0.08, 0.72)
	pos_pill.position = Vector2(1280 - 190, 96)
	pos_pill.size = Vector2(150, 52)
	add_child(pos_pill)
	_pos_l = _mk_label("", 40, Vector2(1280 - 190, 98), HORIZONTAL_ALIGNMENT_CENTER)
	_pos_l.custom_minimum_size = Vector2(150, 48)
	_pos_l.add_theme_font_override("font", FONT_DISPLAY)
	add_child(_pos_l)
	# minimap (top-right, with border)
	var map_bg := ColorRect.new()
	map_bg.color = Color(0.05, 0.04, 0.06, 0.75)
	map_bg.position = Vector2(1280 - 220, 152)
	map_bg.size = Vector2(204, 158)
	add_child(map_bg)
	_map = MinimapScript.new()
	_map.position = Vector2(1280 - 216, 156)
	_map.custom_minimum_size = Vector2(196, 150)
	_map.size = Vector2(196, 150)
	add_child(_map)
	# steering (bottom-left)
	var bl := _mk_button("<", Vector2(36, 720 - 190), Vector2(150, 150), 72)
	var br := _mk_button(">", Vector2(200, 720 - 190), Vector2(150, 150), 72)
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
	# nitro (above handbrake)
	_nitro_btn = _mk_button("N2O", Vector2(1280 - 350, 720 - 480), Vector2(150, 120), 40)
	_nitro_btn.button_down.connect(func(): t_nitro = true)
	_nitro_btn.button_up.connect(func(): t_nitro = false)
	# nitro meter (bottom-left, above steering) with label
	var nitro_cap := _mk_label("NITRO", 18, Vector2(36, 720 - 238))
	nitro_cap.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0, 0.85))
	add_child(nitro_cap)
	_nitro_bar = ProgressBar.new()
	_nitro_bar.min_value = 0
	_nitro_bar.max_value = 100
	_nitro_bar.position = Vector2(36, 720 - 214)
	_nitro_bar.custom_minimum_size = Vector2(314, 16)
	_nitro_bar.size = Vector2(314, 16)
	_nitro_bar.show_percentage = false
	var nbg := StyleBoxFlat.new()
	nbg.bg_color = Color(0.08, 0.10, 0.14, 0.72)
	nbg.set_corner_radius_all(8)
	_nitro_bar.add_theme_stylebox_override("background", nbg)
	var nfill := StyleBoxFlat.new()
	nfill.bg_color = Color(0.25, 0.75, 1.0, 0.95)
	nfill.set_corner_radius_all(8)
	_nitro_bar.add_theme_stylebox_override("fill", nfill)
	add_child(_nitro_bar)
	# photo mode button (top-left, under timer)
	_photo_btn = _mk_button("PHOTO", Vector2(24, 58), Vector2(120, 44), 22)
	_photo_btn.pressed.connect(func(): emit_signal("photo_pressed"))

	# center label (countdown / messages)
	_center_l = _mk_label("", 150, Vector2(0, 200), HORIZONTAL_ALIGNMENT_CENTER)
	_center_l.custom_minimum_size = Vector2(1280, 220)
	_center_l.add_theme_font_override("font", FONT_DISPLAY)
	_center_l.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	_center_l.visible = false
	add_child(_center_l)
	# desktop hint
	_hint_l = _mk_label("Arrows/WASD drive · SPACE handbrake", 20, Vector2(0, 690), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_l.custom_minimum_size = Vector2(1280, 28)
	_hint_l.modulate = Color(1, 1, 1, 0.45)
	add_child(_hint_l)
	# title overlay
	_title_panel = _mk_dim(0.45)
	var tt := _mk_label("TOUGE", 130, Vector2(0, 130), HORIZONTAL_ALIGNMENT_CENTER)
	tt.custom_minimum_size = Vector2(1280, 170)
	tt.add_theme_font_override("font", FONT_DISPLAY)
	tt.add_theme_color_override("font_color", Color(1.0, 0.45, 0.15))
	_title_panel.add_child(tt)
	var tt2 := _mk_label("SUNSET PASS", 44, Vector2(0, 295), HORIZONTAL_ALIGNMENT_CENTER)
	tt2.custom_minimum_size = Vector2(1280, 60)
	tt2.add_theme_font_override("font", FONT_DISPLAY)
	tt2.add_theme_color_override("font_color", Color(1.0, 0.80, 0.45))
	_title_panel.add_child(tt2)
	var ts := _mk_label("head-to-head battle · beat the redline rival", 30, Vector2(0, 360), HORIZONTAL_ALIGNMENT_CENTER)
	ts.custom_minimum_size = Vector2(1280, 50)
	ts.modulate = Color(1, 1, 1, 0.8)
	_title_panel.add_child(ts)
	var go_b := Button.new()
	go_b.text = "TAP TO BATTLE"
	go_b.focus_mode = Control.FOCUS_NONE
	go_b.position = Vector2(1280 / 2 - 170, 430)
	go_b.custom_minimum_size = Vector2(340, 100)
	go_b.size = Vector2(340, 100)
	go_b.add_theme_font_size_override("font_size", 44)
	go_b.add_theme_font_override("font", FONT_DISPLAY)
	go_b.pressed.connect(func(): emit_signal("start_pressed"))
	_title_panel.add_child(go_b)
	# rain toggle on the title (per-run weather)
	_rain_btn = Button.new()
	_rain_btn.text = "RAIN: OFF"
	_rain_btn.focus_mode = Control.FOCUS_NONE
	_rain_btn.position = Vector2(1280 / 2 - 110, 545)
	_rain_btn.custom_minimum_size = Vector2(220, 56)
	_rain_btn.size = Vector2(220, 56)
	_rain_btn.add_theme_font_size_override("font_size", 26)
	_rain_btn.add_theme_font_override("font", FONT_HUD)
	_rain_btn.pressed.connect(_on_rain_toggle)
	_title_panel.add_child(_rain_btn)
	add_child(_title_panel)
	# results panel (hidden)
	_result_panel = _mk_dim()
	_result_l = _mk_label("", 44, Vector2(0, 180), HORIZONTAL_ALIGNMENT_CENTER)
	_result_l.custom_minimum_size = Vector2(1280, 300)
	_result_l.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_result_panel.add_child(_result_l)
	var re := Button.new()
	re.text = "RUN IT BACK"
	re.focus_mode = Control.FOCUS_NONE
	re.position = Vector2(1280 / 2 - 170, 500)
	re.custom_minimum_size = Vector2(340, 90)
	re.size = Vector2(340, 90)
	re.add_theme_font_size_override("font_size", 38)
	re.pressed.connect(func(): emit_signal("restart_pressed"))
	_result_panel.add_child(re)
	_result_panel.visible = false
	add_child(_result_panel)

func _mk_dim(alpha := 0.72) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.03, alpha)
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
	# speed lines fade in past ~60% speed
	var sa := clampf((kmh / 200.0 - 0.55) * 1.6, 0.0, 0.55)
	for line in _speed_lines:
		var c: Color = line.color
		c.a = sa
		line.color = c

func set_battle(gap_m: float, player_ahead: bool) -> void:
	if gap_m < 0.5:
		_gap_l.text = "GAP 0 m"
		_gap_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	elif player_ahead:
		_gap_l.text = "GAP +%.0f m" % gap_m
		_gap_l.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
		_pos_l.text = "1ST"
		_pos_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	else:
		_gap_l.text = "GAP -%.0f m" % gap_m
		_gap_l.add_theme_color_override("font_color", Color(1.0, 0.35, 0.30))
		_pos_l.text = "2ND"
		_pos_l.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))

func set_minimap_track(pts: PackedVector3Array) -> void:
	_map.set_track(pts)

func update_minimap(p1: Vector3, p2: Vector3) -> void:
	_map.set_cars(p1, p2, true)

func show_results(won: bool, time_s: float, gap_s: float, drift: float, best: float, new_best: bool) -> void:
	var head := "YOU WIN!" if won else "RIVAL WINS"
	var nb := "\nNEW BEST!" if new_best else ""
	_result_l.text = "%s\nTime  %s   Gap  %s%.1fs\nDrift  %d pts\nBest  %s%s" % [
		head, _fmt_time(time_s), "+" if won else "-", absf(gap_s),
		int(drift), _fmt_time(best), nb]
	_result_panel.visible = true

func hide_results() -> void:
	_result_panel.visible = false

func _fmt_time(s: float) -> String:
	var m := int(s) / 60
	var sec := s - m * 60
	return "%d:%04.1f" % [m, sec]


func set_photo_ui(on: bool) -> void:
	# hide driving UI for clean screenshots; button becomes EXIT
	for c in get_children():
		if c == _photo_btn:
			continue
		(c as CanvasItem).visible = not on
	_photo_btn.text = "EXIT" if on else "PHOTO"