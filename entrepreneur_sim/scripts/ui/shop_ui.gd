class_name ShopUI
extends Control
## In-shop HUD (built in code): crosshair, context action button, level/XP bar,
## Manage panel (Order / Prices / Store), checkout scanner, toast notifications.

signal action_pressed
signal exit_pressed
signal checkout_finished

const TOUCH := 96.0
const FONT := 28

var _id := ""
var _tab := 0
var _action := Button.new()
var _crosshair := ColorRect.new()
var _level := Label.new()
var _xp := ProgressBar.new()
var _title := Label.new()
var _toasts := VBoxContainer.new()
var _manage := PanelContainer.new()
var _content := VBoxContainer.new()
var _tabs: Array[Button] = []
var _checkout := PanelContainer.new()
var _co_list := Label.new()
var _co_btn := Button.new()
var _co_items: Array[String] = []
var _co_prices: Array[float] = []
var _co_scanned := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = _make_theme()
	visible = false
	_build_hud()
	_build_manage()
	_build_checkout()
	BusinessManager.shop_changed.connect(func(id: String) -> void:
		if id == _id:
			_refresh_header()
			if _manage.visible:
				_fill_tab())


# --- Public API -------------------------------------------------------------------

func show_inside(inside: bool, id: String) -> void:
	_id = id
	visible = inside
	_manage.hide()
	_checkout.hide()
	if inside:
		_title.text = PropertyManager.get_building(id).display_name if PropertyManager.get_building(id) else id
		_refresh_header()


func set_action(text: String) -> void:
	if _action.text != text:
		_action.text = text
	_action.visible = text != "" and not _checkout.visible


func notify(text: String) -> void:
	if not visible:
		return
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_color_override("font_color", Color(0.6, 1, 0.6) if text.begins_with("+") else Color.WHITE)
	_toasts.add_child(l)
	if _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func open_checkout(items: Array[String], prices: Array[float]) -> void:
	_co_items = items.duplicate()
	_co_prices = prices.duplicate()
	_co_scanned = 0
	_manage.hide()
	_checkout.show()
	_action.hide()
	_refresh_checkout()


func close_checkout() -> void:
	_checkout.hide()


# --- HUD --------------------------------------------------------------------------

func _build_hud() -> void:
	_crosshair.size = Vector2(10, 10)
	_crosshair.color = Color(1, 1, 1, 0.85)
	_crosshair.set_anchors_preset(PRESET_CENTER)
	_crosshair.position = -_crosshair.size * 0.5
	_crosshair.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_action.custom_minimum_size = Vector2(TOUCH * 3.2, TOUCH * 1.2)
	_action.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	_action.grow_horizontal = GROW_DIRECTION_BEGIN
	_action.grow_vertical = GROW_DIRECTION_BEGIN
	_action.position -= Vector2(24, 24)
	_action.focus_mode = FOCUS_NONE
	_action.add_theme_font_size_override("font_size", FONT + 2)
	_action.pressed.connect(action_pressed.emit)
	_action.hide()
	add_child(_action)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	top.grow_horizontal = GROW_DIRECTION_BEGIN
	top.position += Vector2(-20, 16)
	top.add_theme_constant_override("separation", 12)
	for spec in [["Manage", _toggle_manage], ["Exit", exit_pressed.emit]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(TOUCH * 1.6, TOUCH * 0.8)
		b.focus_mode = FOCUS_NONE
		b.pressed.connect(spec[1])
		top.add_child(b)
	add_child(top)

	var badge := VBoxContainer.new()
	badge.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	badge.grow_horizontal = GROW_DIRECTION_BOTH
	badge.position.y = 12
	badge.custom_minimum_size.x = 340
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for l in [_level, _title]:
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		row.add_child(l)
	_level.add_theme_color_override("font_color", Color("ffd166"))
	badge.add_child(row)
	_xp.custom_minimum_size = Vector2(320, 14)
	_xp.show_percentage = false
	badge.add_child(_xp)
	_toasts.add_theme_constant_override("separation", 4)
	badge.add_child(_toasts)
	add_child(badge)


func _refresh_header() -> void:
	var s := BusinessManager.get_shop(_id)
	if s == null:
		return
	_level.text = "Lv %d  " % s.level
	_xp.max_value = BusinessCatalog.xp_to_next(s.level)
	_xp.value = s.xp


# --- Manage panel -------------------------------------------------------------------

func _build_manage() -> void:
	_manage.set_anchors_preset(PRESET_CENTER)
	_manage.grow_horizontal = GROW_DIRECTION_BOTH
	_manage.grow_vertical = GROW_DIRECTION_BOTH
	_manage.custom_minimum_size = Vector2(900, 560)
	_manage.mouse_filter = MOUSE_FILTER_STOP
	_manage.hide()
	add_child(_manage)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	_manage.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in 3:
		var b := Button.new()
		b.text = ["Order", "Prices", "Store"][i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(TOUCH * 1.8, TOUCH * 0.75)
		b.focus_mode = FOCUS_NONE
		b.pressed.connect(func() -> void:
			_tab = i
			_fill_tab())
		tabs.add_child(b)
		_tabs.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(TOUCH * 0.8, TOUCH * 0.75)
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(_manage.hide)
	tabs.add_child(close)
	col.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)
	col.add_child(scroll)


func _toggle_manage() -> void:
	if _manage.visible:
		_manage.hide()
		return
	_checkout.hide()
	_manage.custom_minimum_size = Vector2(minf(900, get_viewport_rect().size.x - 40), minf(560, get_viewport_rect().size.y - 140))
	_tabs[_tab].set_pressed_no_signal(true)
	_fill_tab()
	_manage.show()


func _fill_tab() -> void:
	for c in _content.get_children():
		c.queue_free()
	var s := BusinessManager.get_shop(_id)
	if s == null:
		return
	match _tab:
		0: _fill_order(s)
		1: _fill_prices(s)
		2: _fill_store(s)


func _fill_order(s: ShopState) -> void:
	_content.add_child(_text("Boxes are delivered to the yellow mat by the door  (%d/%d)" % [s.boxes.size(), BusinessManager.MAX_BOXES], 22))
	for p: String in BusinessCatalog.products_for(s.business_type):
		var info := BusinessCatalog.info(p)
		var row := _row(info.color)
		row.add_child(_text("%s\nbox of %d · $%.2f each" % [info.name, info.box, info.cost], 24, true))
		var total := float(info.cost) * int(info.box)
		var b := _button("Order $%.0f" % total if s.level >= int(info.lvl) else "Lv %d" % info.lvl)
		b.disabled = s.level < int(info.lvl) or EconomyManager.get_money() < total
		b.pressed.connect(func() -> void: BusinessManager.order_box(_id, p))
		row.add_child(b)


func _fill_prices(s: ShopState) -> void:
	_content.add_child(_text("Higher price = more profit, fewer buyers. Above ~2x market nobody buys.", 22))
	for p: String in BusinessCatalog.products_for(s.business_type):
		var info := BusinessCatalog.info(p)
		if s.level < int(info.lvl):
			continue
		var row := _row(info.color)
		var price := s.price_of(p)
		var chance := int(BusinessCatalog.buy_chance(p, price) * 100)
		row.add_child(_text("%s\nmarket $%.2f · buy chance %d%%" % [info.name, info.market, chance], 24, true))
		var step := maxf(0.1, snappedf(float(info.market) * 0.05, 0.1))
		var minus := _button("-")
		minus.custom_minimum_size.x = TOUCH
		minus.pressed.connect(func() -> void: BusinessManager.set_price(_id, p, s.price_of(p) - step))
		row.add_child(minus)
		var lbl := _text("$%.2f" % price, 28)
		lbl.custom_minimum_size.x = 120
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		var plus := _button("+")
		plus.custom_minimum_size.x = TOUCH
		plus.pressed.connect(func() -> void: BusinessManager.set_price(_id, p, s.price_of(p) + step))
		row.add_child(plus)


func _fill_store(s: ShopState) -> void:
	var open := "Open %02d:00–%02d:00" % [BusinessManager.OPEN_HOUR, BusinessManager.CLOSE_HOUR]
	_content.add_child(_text("Store level %d  (%d/%d XP)   ·   %s" % [s.level, s.xp, BusinessCatalog.xp_to_next(s.level), open], 24))
	_content.add_child(_text("Today: %d customers · %d items · $%.2f revenue · %d lost" % [s.customers_today, s.sold_today, s.revenue_today, s.lost_today], 24))
	var row := _row(Color("2a9d8f"))
	var cashier_text := "Cashier: serves customers and keeps selling while you're away ($%.0f/day)" % BusinessCatalog.CASHIER_WAGE
	row.add_child(_text(cashier_text, 24, true))
	var hire := _button("Fire" if s.cashier else "Hire")
	hire.pressed.connect(func() -> void: BusinessManager.set_cashier(_id, not s.cashier))
	row.add_child(hire)
	var row2 := _row(Color("e76f51"))
	if s.tier < BusinessCatalog.EXPAND_COST.size():
		var cost := BusinessCatalog.EXPAND_COST[s.tier]
		var need := BusinessCatalog.EXPAND_LEVEL[s.tier]
		row2.add_child(_text("Expand store: %d → %d shelves (needs level %d)" % [s.shelves.size(), BusinessCatalog.SHELVES_PER_TIER[s.tier + 1], need], 24, true))
		var ex := _button("Expand $%.0f" % cost)
		ex.disabled = s.level < need or EconomyManager.get_money() < cost
		ex.pressed.connect(func() -> void: BusinessManager.expand(_id))
		row2.add_child(ex)
	else:
		row2.add_child(_text("Store fully expanded (%d shelves)" % s.shelves.size(), 24, true))


func _row(col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var sw := ColorRect.new()
	sw.color = col
	sw.custom_minimum_size = Vector2(16, 64)
	row.add_child(sw)
	_content.add_child(row)
	return row


func _text(t: String, size: int, expand := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if expand:
		l.size_flags_horizontal = SIZE_EXPAND_FILL
	return l


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(TOUCH * 2.0, TOUCH * 0.8)
	b.focus_mode = FOCUS_NONE
	return b


# --- Checkout -----------------------------------------------------------------------

func _build_checkout() -> void:
	_checkout.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_checkout.grow_horizontal = GROW_DIRECTION_BOTH
	_checkout.grow_vertical = GROW_DIRECTION_BEGIN
	_checkout.position.y -= 16
	_checkout.custom_minimum_size = Vector2(620, 0)
	_checkout.mouse_filter = MOUSE_FILTER_STOP
	_checkout.hide()
	add_child(_checkout)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	_checkout.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	col.add_child(_plain("Checkout", FONT + 6))
	_co_list.add_theme_font_size_override("font_size", 24)
	col.add_child(_co_list)
	_co_btn.custom_minimum_size = Vector2(0, TOUCH * 1.1)
	_co_btn.focus_mode = FOCUS_NONE
	_co_btn.add_theme_font_size_override("font_size", FONT + 4)
	_co_btn.pressed.connect(_on_checkout_btn)
	col.add_child(_co_btn)


func _plain(t: String, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	return l


func _refresh_checkout() -> void:
	var lines := PackedStringArray()
	var total := 0.0
	for i in _co_items.size():
		var mark := "✔" if i < _co_scanned else "·"
		lines.append("%s  %s   $%.2f" % [mark, BusinessCatalog.info(_co_items[i]).name, _co_prices[i]])
		if i < _co_scanned:
			total += _co_prices[i]
	lines.append("Total: $%.2f" % total)
	_co_list.text = "\n".join(lines)
	if _co_scanned < _co_items.size():
		_co_btn.text = "Scan item  (%d/%d)" % [_co_scanned + 1, _co_items.size()]
	else:
		_co_btn.text = "Charge card  $%.2f" % total


func _on_checkout_btn() -> void:
	if _co_scanned < _co_items.size():
		_co_scanned += 1
		_refresh_checkout()
		return
	_checkout.hide()
	checkout_finished.emit()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.12, 0.94)
	bg.set_corner_radius_all(22)
	t.set_stylebox("panel", "PanelContainer", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ffd166")
	fill.set_corner_radius_all(7)
	t.set_stylebox("fill", "ProgressBar", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(7)
	t.set_stylebox("background", "ProgressBar", back)
	return t
