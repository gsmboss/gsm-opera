class_name MobileBuildingUI
extends Control
## Touch HUD: money readout, context "interact" button, building bottom sheet.
## Built in code (no .tscn needed). Attach to a full-rect Control under a CanvasLayer.

signal enter_shop_requested(building_id: String)

const TOUCH_MIN := 96.0       # ~48dp at typical phone scale
const SHEET_MAX_WIDTH := 760.0
const FONT_SIZE := 28
const TOAST_SECS := 1.6

var _spot: BuildingSpot       # spot the player currently stands in
var _selected_type := ""
var _type_group := ButtonGroup.new()
var _type_buttons: Array[Button] = [] # pooled, reused across buildings
var _toast_tween: Tween

var _safe := MarginContainer.new()
var _money_label := Label.new()
var _clock_label := Label.new()
var _interact_btn := Button.new()
var _sheet := PanelContainer.new()
var _title := Label.new()
var _stats := Label.new()
var _status := Label.new()
var _buy_btn := Button.new()
var _rent_btn := Button.new()
var _types_box := HFlowContainer.new()
var _start_btn := Button.new()
var _inside_btn := Button.new()
var _toast := Label.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE # let touches pass to 3D / joystick
	theme = _make_theme()
	_build()
	_connect_signals()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	_bind_existing_spots.call_deferred() # after all spots are in tree
	_on_money_changed(EconomyManager.get_money())


## Call for spots spawned at runtime (streamed chunks etc.).
func bind_spot(spot: BuildingSpot) -> void:
	if not spot.player_entered_spot.is_connected(_on_spot_entered):
		spot.player_entered_spot.connect(_on_spot_entered)
		spot.player_exited_spot.connect(_on_spot_exited)


# --- Build --------------------------------------------------------------------

func _build() -> void:
	_safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_safe.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_safe)

	var root := Control.new()
	root.mouse_filter = MOUSE_FILTER_IGNORE
	_safe.add_child(root)

	# Money (top-left)
	_money_label.position = Vector2(8, 8)
	_money_label.add_theme_font_size_override("font_size", FONT_SIZE + 6)
	root.add_child(_money_label)
	_clock_label.position = Vector2(8, 56)
	_clock_label.add_theme_font_size_override("font_size", FONT_SIZE - 4)
	for lbl: Label in [_money_label, _clock_label]: # readable over bright sky
		lbl.add_theme_constant_override("outline_size", 8)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	root.add_child(_clock_label)
	var clock_timer := Timer.new()
	clock_timer.wait_time = 0.5
	clock_timer.autostart = true
	clock_timer.timeout.connect(func() -> void: _clock_label.text = EconomyManager.get_clock_text())
	add_child(clock_timer)

	# Interact button (bottom-right, thumb zone)
	_interact_btn.text = "Enter"
	_interact_btn.custom_minimum_size = Vector2(TOUCH_MIN * 1.6, TOUCH_MIN * 1.6)
	_interact_btn.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	_interact_btn.grow_horizontal = GROW_DIRECTION_BEGIN
	_interact_btn.grow_vertical = GROW_DIRECTION_BEGIN
	_interact_btn.focus_mode = FOCUS_NONE
	_interact_btn.hide()
	root.add_child(_interact_btn)

	# Bottom sheet
	_sheet.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_sheet.grow_horizontal = GROW_DIRECTION_BOTH
	_sheet.grow_vertical = GROW_DIRECTION_BEGIN
	_sheet.mouse_filter = MOUSE_FILTER_STOP # block touches under the sheet
	_sheet.hide()
	root.add_child(_sheet)

	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)
	_sheet.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	var header := HBoxContainer.new()
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", FONT_SIZE + 8)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var close_btn := _make_button("X")
	close_btn.custom_minimum_size.x = TOUCH_MIN
	close_btn.pressed.connect(_close_sheet)
	header.add_child(_title)
	header.add_child(close_btn)
	col.add_child(header)

	col.add_child(_stats)
	_status.modulate = Color(0.75, 0.95, 0.8)
	col.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	for b: Button in [_buy_btn, _rent_btn]:
		_style_touch(b)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		actions.add_child(b)
	col.add_child(actions)

	var biz_label := Label.new()
	biz_label.text = "Business type"
	col.add_child(biz_label)

	_types_box.add_theme_constant_override("h_separation", 10)
	_types_box.add_theme_constant_override("v_separation", 10)
	col.add_child(_types_box)

	_style_touch(_start_btn)
	_start_btn.text = "Start Business"
	col.add_child(_start_btn)

	_style_touch(_inside_btn)
	_inside_btn.text = "Go inside  ▶"
	_inside_btn.add_theme_color_override("font_color", Color("ffd166"))
	col.add_child(_inside_btn)

	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1, 0.55, 0.5, 0)
	col.add_child(_toast)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.12, 0.92)
	bg.set_corner_radius_all(24)
	t.set_stylebox("panel", "PanelContainer", bg)
	return t


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	_style_touch(b)
	return b


func _style_touch(b: Button) -> void:
	b.custom_minimum_size.y = TOUCH_MIN
	b.focus_mode = FOCUS_NONE # no focus ring / no keyboard nav on touch


# --- Wiring -------------------------------------------------------------------

func _connect_signals() -> void:
	_interact_btn.pressed.connect(_open_sheet)
	_buy_btn.pressed.connect(_on_buy)
	_rent_btn.pressed.connect(_on_rent)
	_start_btn.pressed.connect(_on_start)
	_inside_btn.pressed.connect(_on_go_inside)
	EconomyManager.money_changed.connect(_on_money_changed)
	PropertyManager.building_purchased.connect(_on_property_event.unbind(1))
	PropertyManager.building_rented.connect(_on_property_event.unbind(1))
	PropertyManager.business_started.connect(_on_property_event.unbind(2))
	PropertyManager.action_failed.connect(_on_action_failed)


func _bind_existing_spots() -> void:
	for n: Node in get_tree().get_nodes_in_group(BuildingSpot.GROUP):
		bind_spot(n as BuildingSpot)


# --- Spot proximity -----------------------------------------------------------

func _on_spot_entered(spot: BuildingSpot) -> void:
	_spot = spot
	_interact_btn.show()


func _on_spot_exited(spot: BuildingSpot) -> void:
	if spot != _spot:
		return # left an overlapping spot we weren't showing
	_spot = null
	_interact_btn.hide()
	_close_sheet()


# --- Sheet --------------------------------------------------------------------

func _open_sheet() -> void:
	if _spot == null or _spot.data == null:
		return
	_selected_type = ""
	_interact_btn.hide()
	_populate_types(_spot.data)
	_refresh()
	_sheet.show()


func _close_sheet() -> void:
	_sheet.hide()
	if _spot:
		_interact_btn.show()


func _populate_types(data: BuildingData) -> void:
	var types := data.allowed_business_types
	while _type_buttons.size() < types.size(): # grow pool only when needed
		var b := _make_button("")
		b.toggle_mode = true
		b.button_group = _type_group
		b.custom_minimum_size.x = TOUCH_MIN * 2.0
		b.pressed.connect(_on_type_pressed.bind(b))
		_types_box.add_child(b)
		_type_buttons.append(b)
	for i in _type_buttons.size():
		var b := _type_buttons[i]
		b.visible = i < types.size()
		if b.visible:
			b.text = types[i].capitalize()
			b.set_meta(&"type", types[i])
			b.set_pressed_no_signal(false)


func _refresh() -> void:
	if _spot == null or _spot.data == null:
		return
	var d := _spot.data
	var id := d.building_id
	var tenure := PropertyManager.get_tenure(id)
	var biz := PropertyManager.get_business(id)
	var money := EconomyManager.get_money()

	_title.text = d.display_name
	_stats.text = "Price $%s   Rent $%s/day\nFoot traffic %s" % [
		_fmt(d.price), _fmt(d.rent_daily),
		"★".repeat(d.foot_traffic_rating) + "☆".repeat(5 - d.foot_traffic_rating)]
	_status.text = ["Available", "Owned", "Rented"][tenure] # indexed by Tenure enum
	if not biz.is_empty():
		_status.text += "  ·  Running: " + biz.capitalize()

	_buy_btn.text = "Buy $" + _fmt(d.price)
	_buy_btn.disabled = tenure == PropertyManager.Tenure.OWNED or money < d.price
	_rent_btn.text = "Rent $%s/day" % _fmt(d.rent_daily)
	_rent_btn.disabled = tenure != PropertyManager.Tenure.NONE or money < d.rent_daily
	_start_btn.disabled = tenure == PropertyManager.Tenure.NONE \
		or _selected_type.is_empty() or _selected_type == biz
	_inside_btn.visible = not biz.is_empty()


# --- Handlers -----------------------------------------------------------------

func _on_buy() -> void:
	if _spot:
		PropertyManager.purchase(_spot.get_building_id())


func _on_rent() -> void:
	if _spot:
		PropertyManager.rent(_spot.get_building_id())


func _on_start() -> void:
	if _spot and not _selected_type.is_empty():
		PropertyManager.start_business(_spot.get_building_id(), _selected_type)


func _on_go_inside() -> void:
	if _spot == null:
		return
	var id := _spot.get_building_id()
	_sheet.hide()
	enter_shop_requested.emit(id)


func _on_type_pressed(b: Button) -> void:
	_selected_type = b.get_meta(&"type", "")
	_refresh()


func _on_money_changed(amount: float) -> void:
	_money_label.text = "$" + _fmt(amount)
	if _sheet.visible:
		_refresh() # affordability may have changed


func _on_property_event() -> void:
	if _sheet.visible:
		_refresh()


func _on_action_failed(building_id: String, reason: String) -> void:
	if _spot == null or building_id != _spot.get_building_id():
		return
	_toast.text = reason
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)


# --- Layout -------------------------------------------------------------------

## Keeps HUD clear of notches / gesture bars. Converts screen px -> canvas units.
func _apply_safe_area() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var vp := get_viewport_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var k := vp / win
	var m := 16.0
	var left := maxf(safe.position.x * k.x, m)
	var top := maxf(safe.position.y * k.y, m)
	var right := maxf((win.x - safe.end.x) * k.x, m)
	var bottom := maxf((win.y - safe.end.y) * k.y, m)
	# Desktop/editor: safe area is in screen space, not window space -> ignore.
	if OS.get_name() != "Android":
		left = m; top = m; right = m; bottom = m
	_safe.add_theme_constant_override("margin_left", int(left))
	_safe.add_theme_constant_override("margin_top", int(top))
	_safe.add_theme_constant_override("margin_right", int(right))
	_safe.add_theme_constant_override("margin_bottom", int(bottom))
	_sheet.custom_minimum_size.x = minf(SHEET_MAX_WIDTH, vp.x - left - right)


func _fmt(v: float) -> String:
	return String.num(v, 0) if is_equal_approx(v, roundf(v)) else String.num(v, 2)
