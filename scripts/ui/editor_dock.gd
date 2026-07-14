class_name EditorToolsDock
extends PanelContainer
## Right-side editor dock: world actions, tools and the group filter.
## Container-based layout (HBox/VBox) — consistent spacing, no overlap, no
## manual pixel math. Styled to match the block palette panel.

signal save_pressed
signal clear_pressed
signal grav_zone_toggled(active: bool)
signal help_pressed
signal group_filter_changed(group_id: int)

var _grav_btn: Button
var _group_filter: OptionButton


static func make_panel_style() -> StyleBoxFlat:
	## Shared dark panel style (matches the block palette).
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _ready() -> void:
	add_theme_stylebox_override("panel", make_panel_style())

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Row 1: world actions
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	vbox.add_child(row1)
	var save_btn: Button = make_button("Save World", Color(0.25, 0.55, 0.3))
	save_btn.tooltip_text = "Save the world to disk (Ctrl+S)"
	save_btn.pressed.connect(func(): save_pressed.emit())
	row1.add_child(save_btn)
	var clear_btn: Button = make_button("Clear World", Color(0.6, 0.25, 0.25))
	clear_btn.tooltip_text = "Delete everything (undoable with Ctrl+Z)"
	clear_btn.pressed.connect(func(): clear_pressed.emit())
	row1.add_child(clear_btn)

	# Row 2: tools
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	vbox.add_child(row2)
	_grav_btn = make_button("Gravity Zone", Color(0.5, 0.3, 0.7))
	_grav_btn.toggle_mode = true
	_grav_btn.tooltip_text = "Place circular gravity zones (Shift+drag center, then radius)"
	_grav_btn.toggled.connect(func(on: bool): grav_zone_toggled.emit(on))
	row2.add_child(_grav_btn)
	var help_btn: Button = make_button("?", Color(0.3, 0.35, 0.5))
	help_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	help_btn.custom_minimum_size = Vector2(30, 28)
	help_btn.tooltip_text = "Show editor shortcuts"
	help_btn.pressed.connect(func(): help_pressed.emit())
	row2.add_child(help_btn)

	# Row 3: group filter
	var row3: HBoxContainer = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	vbox.add_child(row3)
	var gf_label: Label = Label.new()
	gf_label.text = "Show Group:"
	gf_label.add_theme_font_size_override("font_size", 11)
	gf_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	row3.add_child(gf_label)
	_group_filter = OptionButton.new()
	_group_filter.custom_minimum_size = Vector2(0, 26)
	_group_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_filter.add_theme_font_size_override("font_size", 11)
	_group_filter.focus_mode = Control.FOCUS_NONE
	_group_filter.add_item("All", 0)
	_group_filter.item_selected.connect(func(idx: int):
		group_filter_changed.emit(_group_filter.get_item_id(idx)))
	row3.add_child(_group_filter)


static func make_button(btn_text: String, tint: Color) -> Button:
	## Shared styled button factory — used by the dock and the selection panel
	## so every editor button looks consistent.
	var b: Button = Button.new()
	b.text = btn_text
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(tint.r * 0.4, tint.g * 0.4, tint.b * 0.4, 0.9)
	s.border_color = Color(tint.r, tint.g, tint.b, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	b.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate()
	sh.bg_color = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.95)
	b.add_theme_stylebox_override("hover", sh)
	var sp: StyleBoxFlat = s.duplicate()
	sp.bg_color = Color(tint.r * 0.85, tint.g * 0.85, tint.b * 0.85, 1.0)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


func set_grav_zone_active(active: bool) -> void:
	## Keep the toggle visual in sync when the mode is changed from elsewhere.
	if _grav_btn and _grav_btn.button_pressed != active:
		_grav_btn.set_pressed_no_signal(active)


func rebuild_group_items() -> void:
	## Refresh the group filter dropdown from WorldManager, keeping selection.
	if not _group_filter:
		return
	var prev: int = WorldManager.active_group_filter
	_group_filter.clear()
	_group_filter.add_item("All", 0)
	for g in WorldManager.block_groups:
		_group_filter.add_item(g.name, g.id)
	for i in range(_group_filter.item_count):
		if _group_filter.get_item_id(i) == prev:
			_group_filter.selected = i
			return
	_group_filter.selected = 0
	WorldManager.active_group_filter = 0
