extends Node
## Repro: drive via the actual GAS Button's button_down signal (like a real press).

var _main = null
var _frame := 0
var _gas_btn: Button = null

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	add_child(_main)
	_main._on_start()
	_main._state = 2
	_main._car.active = true
	# find the GAS button among the hud's children
	for c in _main._hud.get_children():
		if c is Button and c.text == "GAS":
			_gas_btn = c
	print("GAS button found: ", _gas_btn != null)
	_gas_btn.emit_signal("button_down")
	print("t_gas after button_down: ", _main._hud.t_gas)

func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 300:
		print("f=300 t_gas=", _main._hud.t_gas, " fspeed=", _main._car.f_speed,
			" vel=", _main._car.vel, " seg=", _main._car._seg)
	if _frame == 600:
		print("f=600 t_gas=", _main._hud.t_gas, " fspeed=", _main._car.f_speed,
			" vel=", _main._car.vel, " seg=", _main._car._seg,
			" pos=", _main._car.global_position)
