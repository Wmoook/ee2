extends Node2D

var _hover: Vector2i = Vector2i(-1, -1)
var _drag_start: Vector2i = Vector2i(-1, -1)
var _shift_dragging: bool = false
var _last_place: Vector2i = Vector2i(-999, -999)

# Line drawing mode
var _line_mode: bool = false
var _line_start: Vector2 = Vector2(-1, -1)
var _line_drawing: bool = false

# Selection mode
var _selection: Rect2i = Rect2i()
var _has_selection: bool = false
var _sel_start: Vector2i = Vector2i()
var _sel_dragging: bool = false

# Rotation wheel
var _rot_dragging: bool = false
var _rot_angle: float = 0.0
var _move_dragging: bool = false
var _move_start: Vector2i = Vector2i()
var _move_blocks: Array = []
var _rot_last_snap: int = 0  # Last snapped rotation count
const ROT_WHEEL_RADIUS: float = 40.0

# Aligned placement mode
var _align_mode: bool = false
var _align_angle: float = 0.0
var _align_origin: Vector2 = Vector2.ZERO
var _align_block_id: int = 0
# Aligned selection (in rotated local grid coords)
var _align_sel_start: Vector2 = Vector2.ZERO
var _align_sel_end: Vector2 = Vector2.ZERO
var _align_sel_dragging: bool = false
var _align_has_sel: bool = false
var _align_drag_angle: float = 0.0
var _align_wheel_pos: Vector2 = Vector2.ZERO
var _align_sel_indices: Array = []
var _align_move_start: Vector2 = Vector2.ZERO

var _spin_btn: Button
var _spin_slider: HSlider
var _spin_label: Label
var _spin_panel: VBoxContainer
var _align_btn: Button
var _reset_btn: Button
var _ui_layer: CanvasLayer
var _spin_speed_val: float = 45.0

func _ready() -> void:
	z_index = 5
	GameState.edit_mode_changed.connect(func(_e: bool): queue_redraw())
	# UI layer for screen-space buttons
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 11
	add_child(_ui_layer)
	# Spin panel on right side
	_spin_panel = VBoxContainer.new()
	_spin_panel.visible = false
	_ui_layer.add_child(_spin_panel)

	_spin_label = Label.new()
	_spin_label.text = "Speed: 45 deg/s"
	_spin_label.add_theme_font_size_override("font_size", 11)
	_spin_label.add_theme_color_override("font_color", Color.WHITE)
	_spin_panel.add_child(_spin_label)

	_spin_slider = HSlider.new()
	_spin_slider.min_value = -360
	_spin_slider.max_value = 360
	_spin_slider.step = 5
	_spin_slider.value = 45
	_spin_slider.custom_minimum_size = Vector2(140, 20)
	_spin_slider.value_changed.connect(_on_spin_speed_changed)
	_spin_panel.add_child(_spin_slider)

	_spin_btn = Button.new()
	_spin_btn.text = "Spin Object"
	_spin_btn.custom_minimum_size = Vector2(140, 28)
	_spin_btn.add_theme_font_size_override("font_size", 11)
	_spin_btn.pressed.connect(_on_spin_pressed)
	_spin_panel.add_child(_spin_btn)

	_align_btn = Button.new()
	_align_btn.text = "Align Grid"
	_align_btn.custom_minimum_size = Vector2(140, 28)
	_align_btn.add_theme_font_size_override("font_size", 11)
	_align_btn.pressed.connect(_on_align_pressed)
	_spin_panel.add_child(_align_btn)

	# Reset grid button - always visible in edit mode (separate from panel)
	_reset_btn = Button.new()
	_reset_btn.text = "Reset Grid"
	_reset_btn.size = Vector2(90, 25)
	_reset_btn.add_theme_font_size_override("font_size", 10)
	_reset_btn.pressed.connect(func():
		_align_mode = false
		_align_btn.text = "Align Grid"
		WorldManager.free_blocks.clear()
		_free_originals.clear()
		_deselect()
		queue_redraw())
	_ui_layer.add_child(_reset_btn)
	# Position will be set in _process

func _input(event: InputEvent) -> void:
	if not GameState.is_edit_mode:
		return
	if event.is_action_pressed("block_next"):
		GameState.cycle_block(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("block_prev"):
		GameState.cycle_block(false)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_line_mode = not _line_mode
			_line_drawing = false
			_deselect()
			queue_redraw()
		# R = rotate 90° CW (group if selection, single block otherwise)
		if event.keycode == KEY_R or event.physical_keycode == KEY_R:
			if _has_selection:
				_rotate_group_90()
			else:
				# Single block under cursor: rotate in place by 90°
				var t: Vector2i = _get_tile()
				if WorldManager.get_tile(t.x, t.y) != 0:
					var cur: int = WorldManager.get_rotation(t.x, t.y)
					WorldManager.set_rotation(t.x, t.y, (cur + 90) % 360)
		# Delete/Backspace = clear selected blocks
		if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and _has_selection:
			_clear_selection()
		# Escape = deselect or exit align mode
		if event.keycode == KEY_ESCAPE:
			if _align_mode:
				_align_mode = false
			elif _has_selection:
				_deselect()
			queue_redraw()

	# Rotation wheel input (checked FIRST, before UI/line mode)
	if (_has_selection or _align_has_sel) and not _line_mode:
		var wheel_center: Vector2
		if _align_has_sel:
			wheel_center = _align_wheel_pos
		else:
			wheel_center = _get_selection_center_world()
		var mouse_world: Vector2 = get_global_mouse_position()
		var dist_to_wheel: float = mouse_world.distance_to(wheel_center)

		if _rot_dragging:
			if event is InputEventMouseMotion:
				var raw_angle: float = (mouse_world - wheel_center).angle()
				var deg: float = rad_to_deg(raw_angle - _rot_angle)
				# Snap to 45° (Ctrl = free)
				var snap_deg: float = deg
				if not Input.is_key_pressed(KEY_CTRL):
					snap_deg = round(deg / 45.0) * 45.0
				# Rotate all free blocks around the group center
				_rotate_free_blocks(snap_deg)
				_align_drag_angle = snap_deg
				queue_redraw()
			if event.is_action_released("place_block"):
				_rot_dragging = false
				if _align_has_sel and _align_drag_angle != 0:
					_align_drag_angle = 0
					# Set grid directly from actual block state - no math drift
					if _align_sel_indices.size() > 0 and _align_sel_indices[0] < WorldManager.free_blocks.size():
						var ref_fb: Dictionary = WorldManager.free_blocks[_align_sel_indices[0]]
						_align_angle = ref_fb.rotation
						_align_origin = ref_fb.pos
			return

		# Only trigger rotation when clicking ON the wheel ring (±10px of circle)
		if event.is_action_pressed("place_block") and dist_to_wheel > ROT_WHEEL_RADIUS - 10 and dist_to_wheel < ROT_WHEEL_RADIUS + 10:
			_rot_dragging = true
			_rot_angle = (mouse_world - wheel_center).angle()
			if _align_has_sel:
				_lift_aligned_to_free(wheel_center)
			else:
				_lift_to_free()
			get_viewport().set_input_as_handled()
			return

		# Click inside selection (not on wheel ring) = start dragging to move
		var tile: Vector2i = _get_tile()
		var in_sel: bool = tile.x >= _selection.position.x and tile.x < _selection.position.x + _selection.size.x and tile.y >= _selection.position.y and tile.y < _selection.position.y + _selection.size.y

		if _move_dragging:
			if event is InputEventMouseMotion:
				var cur: Vector2i = _get_tile()
				var dx: int = cur.x - _move_start.x
				var dy: int = cur.y - _move_start.y
				if dx != 0 or dy != 0:
					_apply_move(dx, dy)
					_move_start = cur
				queue_redraw()
			if event.is_action_released("place_block"):
				_move_dragging = false
			return

		if event.is_action_pressed("place_block") and in_sel:
			_move_dragging = true
			_move_start = tile
			# Store blocks for moving
			_move_blocks.clear()
			for my in range(_selection.position.y, _selection.position.y + _selection.size.y):
				for mx in range(_selection.position.x, _selection.position.x + _selection.size.x):
					var bid: int = WorldManager.get_tile(mx, my)
					if bid != 0:
						_move_blocks.append({"rx": mx - _selection.position.x, "ry": my - _selection.position.y, "id": bid, "rot": WorldManager.get_rotation(mx, my)})
			get_viewport().set_input_as_handled()
			return

	if _is_mouse_over_ui():
		return

	# Aligned mode: shift = rotated select, normal = place
	if _align_mode and Input.is_key_pressed(KEY_SHIFT):
		if event.is_action_pressed("place_block"):
			_align_sel_start = _get_aligned_local(get_global_mouse_position())
			_align_sel_end = _align_sel_start
			_align_sel_dragging = true
			_align_has_sel = false
			_align_sel_indices.clear()
			_has_selection = false
		if event is InputEventMouseMotion and _align_sel_dragging:
			_align_sel_end = _get_aligned_local(get_global_mouse_position())
			queue_redraw()
		if event.is_action_released("place_block") and _align_sel_dragging:
			_align_sel_end = _get_aligned_local(get_global_mouse_position())
			_align_sel_dragging = false
			_align_has_sel = true
			_has_selection = true
			# Store indices of blocks in selection
			_align_sel_indices.clear()
			var _finv: float = deg_to_rad(-_align_angle)
			var _fmn: Vector2 = Vector2(minf(_align_sel_start.x, _align_sel_end.x), minf(_align_sel_start.y, _align_sel_end.y))
			var _fmx: Vector2 = Vector2(maxf(_align_sel_start.x, _align_sel_end.x), maxf(_align_sel_start.y, _align_sel_end.y))
			for _fi in range(WorldManager.free_blocks.size()):
				var _fb: Dictionary = WorldManager.free_blocks[_fi]
				var _fc: Vector2 = _fb.pos + Vector2(8, 8)
				var _fl: Vector2 = (_fc - _align_origin).rotated(_finv)
				var _gx: float = floor(_fl.x / 16.0)
				var _gy: float = floor(_fl.y / 16.0)
				if _gx >= _fmn.x and _gx <= _fmx.x and _gy >= _fmn.y and _gy <= _fmx.y:
					_align_sel_indices.append(_fi)
			# Store wheel center
			var _bar: float = deg_to_rad(_align_angle)
			var _bvgo: Vector2 = _align_origin + Vector2(8, 8) + Vector2(-8, -8).rotated(_bar)
			var _bmn: Vector2 = Vector2(minf(_align_sel_start.x, _align_sel_end.x), minf(_align_sel_start.y, _align_sel_end.y))
			var _bmx: Vector2 = Vector2(maxf(_align_sel_start.x, _align_sel_end.x) + 1, maxf(_align_sel_start.y, _align_sel_end.y) + 1)
			var _c0: Vector2 = _bvgo + (_bmn * 16.0).rotated(_bar)
			var _c2: Vector2 = _bvgo + (_bmx * 16.0).rotated(_bar)
			_align_wheel_pos = (_c0 + _c2) / 2.0
			queue_redraw()
		if event is InputEventKey and event.pressed and not event.echo:
			if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and _align_has_sel:
				_delete_aligned_selection()
		return

	if _align_mode:
		# Move-drag: click inside aligned selection to move blocks
		if _align_has_sel and not _align_sel_dragging:
			var mg: Vector2 = get_global_mouse_position()
			# Check if mouse is near any selected block (not grid coords)
			var in_asel: bool = false
			for si in _align_sel_indices:
				if si < WorldManager.free_blocks.size():
					var sfb: Dictionary = WorldManager.free_blocks[si]
					if mg.distance_to(sfb.pos + Vector2(8, 8)) < 16.0:
						in_asel = true
						break
			if _move_dragging:
				if event is InputEventMouseMotion:
					var cur_snap: Vector2 = _get_aligned_snap(get_global_mouse_position())
					var offset: Vector2 = cur_snap - _align_move_start
					if offset.length() > 0.5:
						for si in _align_sel_indices:
							if si < WorldManager.free_blocks.size():
								WorldManager.free_blocks[si].pos += offset
						_align_origin += offset
						_align_wheel_pos += offset
						_align_move_start = cur_snap
					queue_redraw()
				if event.is_action_released("place_block"):
					_move_dragging = false
				return
			if event.is_action_pressed("place_block") and in_asel:
				_move_dragging = true
				_align_move_start = _get_aligned_snap(mg)
				get_viewport().set_input_as_handled()
				return
		var _place_aligned: bool = false
		if event.is_action_pressed("place_block"):
			_place_aligned = true
		if event is InputEventMouseMotion and Input.is_action_pressed("place_block"):
			_place_aligned = true
		if _place_aligned:
			var snap_pos: Vector2 = _get_aligned_snap(get_global_mouse_position())
			# Don't place if one already exists there
			var exists: bool = false
			for fb in WorldManager.free_blocks:
				if fb.pos.distance_to(snap_pos) < 2.0:
					exists = true
					break
			if not exists:
				WorldManager.free_blocks.append({"pos": snap_pos, "id": GameState.selected_block_id, "rotation": _align_angle})
			queue_redraw()
		if event.is_action_pressed("remove_block") or (event is InputEventMouseMotion and Input.is_action_pressed("remove_block")):
			var mouse: Vector2 = get_global_mouse_position()
			var best_i: int = -1
			var best_d: float = 12.0
			for i in range(WorldManager.free_blocks.size()):
				var fb: Dictionary = WorldManager.free_blocks[i]
				var d: float = mouse.distance_to(fb.pos + Vector2(8, 8))
				if d < best_d:
					best_d = d
					best_i = i
			if best_i >= 0:
				WorldManager.free_blocks.remove_at(best_i)
				queue_redraw()
		if event is InputEventMouseMotion:
			queue_redraw()
		return

	# Line mode
	if _line_mode:
		if event.is_action_pressed("place_block"):
			_line_start = get_global_mouse_position()
			_line_drawing = true
		if event.is_action_released("place_block") and _line_drawing:
			var end_pos: Vector2 = get_global_mouse_position()
			if _line_start.distance_to(end_pos) > 8:
				WorldManager.add_line(_line_start, end_pos, Color(0.6, 0.6, 0.7, 1.0), 3.0)
			_line_drawing = false
		if event.is_action_pressed("remove_block"):
			WorldManager.remove_line_near(get_global_mouse_position(), 12.0)
		if event is InputEventMouseMotion:
			queue_redraw()
		return

	var shift: bool = Input.is_key_pressed(KEY_SHIFT)

	if event.is_action_pressed("place_block"):
		var t: Vector2i = _get_tile()
		if shift:
			if _has_selection:
				_deselect()
				_rot_dragging = false
				queue_redraw()
				return
			# Shift+drag = box select
			_sel_start = t
			_sel_dragging = true
		elif Input.is_key_pressed(KEY_CTRL):
			# Ctrl+drag = line fill
			_drag_start = t
			_shift_dragging = true
		else:
			_place_at(t)
			_last_place = t

	if event.is_action_released("place_block"):
		if _sel_dragging:
			# Finalize box selection
			var t: Vector2i = _get_tile()
			var x0: int = mini(_sel_start.x, t.x)
			var y0: int = mini(_sel_start.y, t.y)
			var x1: int = maxi(_sel_start.x, t.x)
			var y1: int = maxi(_sel_start.y, t.y)
			_selection = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
			_has_selection = true
			_sel_dragging = false
		if _shift_dragging and _drag_start.x >= 0:
			var t: Vector2i = _get_tile()
			_fill_line(_drag_start, t, GameState.selected_block_id)
			_shift_dragging = false
			_drag_start = Vector2i(-1, -1)
		_last_place = Vector2i(-999, -999)

	if event.is_action_pressed("remove_block"):
		var t: Vector2i = _get_tile()
		if Input.is_key_pressed(KEY_CTRL):
			_drag_start = t
			_shift_dragging = true
		else:
			_erase_at(t)

	if event.is_action_released("remove_block"):
		if _shift_dragging and _drag_start.x >= 0:
			var t: Vector2i = _get_tile()
			_fill_line(_drag_start, t, 0)
			_shift_dragging = false
			_drag_start = Vector2i(-1, -1)

	if event is InputEventMouseMotion:
		_hover = _get_tile()
		queue_redraw()
		if not shift and not _shift_dragging:
			if Input.is_action_pressed("place_block"):
				var t: Vector2i = _get_tile()
				if t != _last_place:
					_place_at(t)
					_last_place = t
			elif Input.is_action_pressed("remove_block"):
				_erase_at(_get_tile())

func _is_mouse_over_ui() -> bool:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var panel_w: float = 16 * 36 + 32
	var panel_h: float = 300.0
	if mouse.x > vp_size.x - panel_w - 16 and mouse.y < panel_h + 16:
		return true
	# Camera pad on left
	if mouse.x < 140 and mouse.y > vp_size.y / 2 - 70 and mouse.y < vp_size.y / 2 + 70:
		return true
	# Spin panel on right
	if _spin_panel and _spin_panel.visible and mouse.x > vp_size.x - 170 and mouse.y > vp_size.y / 2 - 50 and mouse.y < vp_size.y / 2 + 50:
		return true
	return false

func _on_align_pressed() -> void:
	if _align_mode:
		_align_mode = false
		_align_btn.text = "Align Grid"
		return
	# Find rotation from free blocks in selection or any free blocks
	var rot: float = 0.0
	var origin: Vector2 = Vector2.ZERO
	var found: bool = false
	if _has_selection:
		var sel_rect: Rect2 = Rect2(
			_selection.position.x * 16.0, _selection.position.y * 16.0,
			_selection.size.x * 16.0, _selection.size.y * 16.0)
		for fb in WorldManager.free_blocks:
			if sel_rect.has_point(fb.pos + Vector2(8, 8)):
				rot = fb.rotation
				origin = fb.pos
				found = true
				break
	if not found:
		for fb in WorldManager.free_blocks:
			if GameState.is_solid(fb.id) and absf(fb.rotation) > 0.1:
				rot = fb.rotation
				origin = fb.pos
				found = true
				break
	if found:
		_align_angle = rot
		_align_origin = origin
		_align_mode = true
		_align_btn.text = "Exit Align"
		_deselect()
		queue_redraw()

func _on_spin_speed_changed(val: float) -> void:
	_spin_speed_val = val
	_spin_label.text = "Speed: %d deg/s" % int(val)
	# Update ALL currently spinning blocks (they may have moved outside selection)
	for fb in WorldManager.free_blocks:
		if fb.has("base_offset"):  # Has been set up for spinning
			fb.spin = val

func _on_spin_pressed() -> void:
	if not _has_selection:
		return
	_lift_to_free()
	var sel_rect: Rect2 = Rect2(
		_selection.position.x * 16.0, _selection.position.y * 16.0,
		_selection.size.x * 16.0, _selection.size.y * 16.0)
	var center: Vector2 = sel_rect.position + sel_rect.size / 2.0
	var any_spinning: bool = false
	for fb in WorldManager.free_blocks:
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		if sel_rect.has_point(fc):
			if fb.has("spin") and fb.spin != 0:
				any_spinning = true
				break
	for fb in WorldManager.free_blocks:
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		if sel_rect.has_point(fc):
			if any_spinning:
				fb["spin"] = 0.0
				fb.erase("pivot")
				fb.erase("base_offset")
				fb.erase("base_rot")
				fb.erase("spin_angle")
			else:
				fb["spin"] = _spin_speed_val
				fb["pivot"] = center
				fb["base_offset"] = fb.pos + Vector2(8, 8) - center
				fb["base_rot"] = fb.rotation
				fb["spin_angle"] = 0.0
	_spin_btn.text = "Stop Spin" if not any_spinning else "Spin Object"

func _process(_delta: float) -> void:
	# Spin panel positioning
	if _spin_panel:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		_spin_panel.visible = (_has_selection or _align_mode) and GameState.is_edit_mode
		_spin_panel.position = Vector2(vp_size.x - 160, vp_size.y / 2 - 40)
	# Reset button always visible in edit mode
	if _reset_btn:
		var vp_size2: Vector2 = get_viewport().get_visible_rect().size
		_reset_btn.visible = GameState.is_edit_mode
		_reset_btn.position = Vector2(vp_size2.x - 110, 8)
	# Rotate spinning free blocks (rigid body from base positions)
	if WorldManager.free_blocks.size() > 0:
		for fb in WorldManager.free_blocks:
			if fb.has("base_offset") and fb.has("pivot"):
				fb.spin_angle += fb.spin * _delta
				var rad: float = deg_to_rad(fb.spin_angle)
				var pivot: Vector2 = fb.pivot
				var new_pos: Vector2 = pivot + fb.base_offset.rotated(rad) - Vector2(8, 8)
				fb.pos = new_pos
				fb.rotation = fb.base_rot + fb.spin_angle
	if GameState.is_edit_mode:
		queue_redraw()

func _draw() -> void:
	if not GameState.is_edit_mode:
		return

	# Use canvas transform for correct viewport bounds
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var vp_size: Vector2 = get_viewport_rect().size
	var inv: Transform2D = ct.affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var br: Vector2 = inv * vp_size
	var sx: int = maxi(0, int(floor(tl.x / 16.0)) - 1)
	var sy: int = maxi(0, int(floor(tl.y / 16.0)) - 1)
	var ex: int = mini(WorldManager.world_width, int(ceil(br.x / 16.0)) + 1)
	var ey: int = mini(WorldManager.world_height, int(ceil(br.y / 16.0)) + 1)

	var gc: Color = Color(1, 1, 1, 0.04)
	for gx in range(sx, ex + 1):
		draw_line(Vector2(gx * 16, sy * 16), Vector2(gx * 16, ey * 16), gc, 0.5)
	for gy in range(sy, ey + 1):
		draw_line(Vector2(sx * 16, gy * 16), Vector2(ex * 16, gy * 16), gc, 0.5)

	# Aligned placement mode: show rotated grid cursor
	if _align_mode:
		var mouse: Vector2 = get_global_mouse_position()
		var snap: Vector2 = _get_aligned_snap(mouse)
		var rad: float = deg_to_rad(_align_angle)
		var center: Vector2 = snap + Vector2(8, 8)
		draw_set_transform(center, deg_to_rad(_align_angle), Vector2.ONE)
		draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 1.0, 0.3, 0.4), true)
		draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 1.0, 0.3, 0.8), false, 1.5)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# Draw rotated grid lines
		var grid_col: Color = Color(0.3, 1.0, 0.3, 0.08)
		var go: Vector2 = center + Vector2(-8, -8).rotated(rad)
		for i in range(-20, 21):
			draw_line(go + Vector2(i * 16, -400).rotated(rad), go + Vector2(i * 16, 400).rotated(rad), grid_col, 0.5)
			draw_line(go + Vector2(-400, i * 16).rotated(rad), go + Vector2(400, i * 16).rotated(rad), grid_col, 0.5)

	# Aligned selection: draw from actual block positions in rotated local space
	if _align_mode and (_align_sel_dragging or _align_has_sel):
		var s: Vector2 = _align_sel_start
		var e: Vector2 = _align_sel_end if not _align_sel_dragging else _get_aligned_local(get_global_mouse_position())
		var mn: Vector2 = Vector2(minf(s.x, e.x), minf(s.y, e.y))
		var mx2: Vector2 = Vector2(maxf(s.x, e.x) + 1, maxf(s.y, e.y) + 1)
		# During drag: grid-based preview. After release: block-based exact.
		if _align_sel_dragging:
			var dar: float = deg_to_rad(_align_angle)
			var dvgo: Vector2 = _align_origin + Vector2(8, 8) + Vector2(-8, -8).rotated(dar)
			var dc0: Vector2 = dvgo + (mn * 16.0).rotated(dar)
			var dc1: Vector2 = dvgo + (Vector2(mx2.x, mn.y) * 16.0).rotated(dar)
			var dc2: Vector2 = dvgo + (mx2 * 16.0).rotated(dar)
			var dc3: Vector2 = dvgo + (Vector2(mn.x, mx2.y) * 16.0).rotated(dar)
			var dsc: Color = Color(0.3, 0.6, 1.0, 0.5)
			draw_line(dc0, dc1, dsc, 1.5)
			draw_line(dc1, dc2, dsc, 1.5)
			draw_line(dc2, dc3, dsc, 1.5)
			draw_line(dc3, dc0, dsc, 1.5)

		# Selection box from stored block indices - always exact
		var cur_angle: float = _align_angle + _align_drag_angle
		var inv_r: float = deg_to_rad(-cur_angle)
		var fwd_r: float = deg_to_rad(cur_angle)
		var bmin: Vector2 = Vector2(INF, INF)
		var bmax: Vector2 = Vector2(-INF, -INF)
		var found_any: bool = false
		for idx in _align_sel_indices:
			if idx < WorldManager.free_blocks.size():
				var fb: Dictionary = WorldManager.free_blocks[idx]
				var fc: Vector2 = fb.pos + Vector2(8, 8)
				var loc: Vector2 = (fc - _align_wheel_pos).rotated(inv_r)
				bmin.x = minf(bmin.x, loc.x - 8); bmin.y = minf(bmin.y, loc.y - 8)
				bmax.x = maxf(bmax.x, loc.x + 8); bmax.y = maxf(bmax.y, loc.y + 8)
				found_any = true
		var c0: Vector2; var c1: Vector2; var c2: Vector2; var c3: Vector2
		if found_any:
			c0 = _align_wheel_pos + Vector2(bmin.x, bmin.y).rotated(fwd_r)
			c1 = _align_wheel_pos + Vector2(bmax.x, bmin.y).rotated(fwd_r)
			c2 = _align_wheel_pos + Vector2(bmax.x, bmax.y).rotated(fwd_r)
			c3 = _align_wheel_pos + Vector2(bmin.x, bmax.y).rotated(fwd_r)
		else:
			c0 = Vector2.ZERO; c1 = c0; c2 = c0; c3 = c0
		var sel_col: Color = Color(0.3, 0.6, 1.0, 0.7)
		draw_line(c0, c1, sel_col, 2.0)
		draw_line(c1, c2, sel_col, 2.0)
		draw_line(c2, c3, sel_col, 2.0)
		draw_line(c3, c0, sel_col, 2.0)

	# Hover highlight
	if not _align_mode and _hover.x >= 0 and _hover.y >= 0:
		var hr: Rect2 = Rect2(Vector2(_hover.x * 16, _hover.y * 16), Vector2(16, 16))
		draw_rect(hr, Color(1, 1, 1, 0.25), false, 1.5)

	# Shift-drag preview line
	if _shift_dragging and _drag_start.x >= 0:
		var end: Vector2i = _hover
		var points: Array = _get_line_points(_drag_start, end)
		for p in points:
			var pr: Rect2 = Rect2(Vector2(p.x * 16, p.y * 16), Vector2(16, 16))
			draw_rect(pr, Color(1, 1, 0.5, 0.25), true)
			draw_rect(pr, Color(1, 1, 0.5, 0.5), false, 1.0)

	# Draw all placed lines
	for line in WorldManager.lines:
		draw_line(line.start, line.end, line.color, line.width, true)

	# Line mode preview
	if _line_mode and _line_drawing:
		var mouse: Vector2 = get_global_mouse_position()
		draw_line(_line_start, mouse, Color(1, 1, 0.5, 0.6), 3.0, true)

	# Box selection preview while dragging
	if _sel_dragging:
		var end: Vector2i = _hover
		var x0: int = mini(_sel_start.x, end.x)
		var y0: int = mini(_sel_start.y, end.y)
		var x1: int = maxi(_sel_start.x, end.x)
		var y1: int = maxi(_sel_start.y, end.y)
		var sr: Rect2 = Rect2(Vector2(x0 * 16, y0 * 16), Vector2((x1 - x0 + 1) * 16, (y1 - y0 + 1) * 16))
		draw_rect(sr, Color(0.3, 0.6, 1.0, 0.15), true)
		draw_rect(sr, Color(0.3, 0.6, 1.0, 0.7), false, 2.0)

	# Rotation wheel for aligned selection
	if _align_mode and _align_has_sel and _align_sel_indices.size() > 0:
		var awc: Vector2 = _align_wheel_pos
		var wc2: Color = Color(0.4, 0.7, 1.0, 0.5) if not _rot_dragging else Color(0.5, 0.9, 1.0, 0.8)
		draw_arc(awc, ROT_WHEEL_RADIUS, 0, TAU, 32, wc2, 2.0)
		for tick2 in range(4):
			var a2: float = tick2 * PI / 2.0
			draw_line(awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS - 6), awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS + 6), wc2, 2.0)
		for tick2 in range(4):
			var a2: float = tick2 * PI / 2.0 + PI / 4.0
			draw_line(awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS - 3), awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS + 3), Color(wc2, 0.3), 1.0)
		var ha2: float = 0.0
		if _rot_dragging:
			ha2 = (get_global_mouse_position() - awc).angle()
		draw_circle(awc + Vector2(cos(ha2), sin(ha2)) * ROT_WHEEL_RADIUS, 5.0, Color(0.5, 0.8, 1.0, 0.9))

	# Existing selection highlight + rotation wheel (not in align mode)
	if _has_selection and not _align_mode:
		var sr: Rect2 = Rect2(
			Vector2(_selection.position.x * 16, _selection.position.y * 16),
			Vector2(_selection.size.x * 16, _selection.size.y * 16))
		draw_rect(sr, Color(0.2, 0.5, 1.0, 0.1), true)
		draw_rect(sr, Color(0.2, 0.5, 1.0, 0.6), false, 1.5)

		# Rotation wheel
		var wc: Vector2 = _get_selection_center_world()
		var wheel_col: Color = Color(0.4, 0.7, 1.0, 0.5) if not _rot_dragging else Color(0.5, 0.9, 1.0, 0.8)
		draw_arc(wc, ROT_WHEEL_RADIUS, 0, TAU, 32, wheel_col, 2.0)
		# 4 tick marks at 0°, 90°, 180°, 270°
		for tick in range(4):
			var a: float = tick * PI / 2.0
			var inner: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS - 6)
			var outer: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS + 6)
			draw_line(inner, outer, wheel_col, 2.0)
		# 4 more at 45° intervals (thinner)
		for tick in range(4):
			var a: float = tick * PI / 2.0 + PI / 4.0
			var inner: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS - 3)
			var outer: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS + 3)
			draw_line(inner, outer, Color(wheel_col, 0.3), 1.0)
		# Handle dot - show current drag angle or mouse direction
		var handle_angle: float = 0.0
		if _rot_dragging:
			var mw: Vector2 = get_global_mouse_position()
			handle_angle = (mw - wc).angle()
		var handle_pos: Vector2 = wc + Vector2(cos(handle_angle), sin(handle_angle)) * ROT_WHEEL_RADIUS
		draw_circle(handle_pos, 5.0, Color(0.5, 0.8, 1.0, 0.9))

func _get_selection_center_world() -> Vector2:
	var cx: float = (_selection.position.x + _selection.size.x / 2.0) * 16.0
	var cy: float = (_selection.position.y + _selection.size.y / 2.0) * 16.0
	return Vector2(cx, cy)

func _get_tile() -> Vector2i:
	var m: Vector2 = get_global_mouse_position()
	return Vector2i(int(floor(m.x / 16.0)), int(floor(m.y / 16.0)))

func _place_at(t: Vector2i) -> void:
	if t.x <= 0 or t.x >= WorldManager.world_width - 1: return
	if t.y <= 0 or t.y >= WorldManager.world_height - 1: return
	WorldManager.set_tile(t.x, t.y, GameState.selected_block_id)

func _erase_at(t: Vector2i) -> void:
	if t.x <= 0 or t.x >= WorldManager.world_width - 1: return
	if t.y <= 0 or t.y >= WorldManager.world_height - 1: return
	WorldManager.set_fg_tile(t.x, t.y, 0)
	WorldManager.set_bg_tile(t.x, t.y, 0)

func _fill_line(from: Vector2i, to: Vector2i, block_id: int) -> void:
	var points: Array = _get_line_points(from, to)
	for p in points:
		if p.x <= 0 or p.x >= WorldManager.world_width - 1: continue
		if p.y <= 0 or p.y >= WorldManager.world_height - 1: continue
		if block_id == 0:
			WorldManager.set_fg_tile(p.x, p.y, 0)
			WorldManager.set_bg_tile(p.x, p.y, 0)
		else:
			WorldManager.set_tile(p.x, p.y, block_id)

func _get_line_points(from: Vector2i, to: Vector2i) -> Array:
	# Bresenham's line algorithm
	var points: Array = []
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var err: int = dx - dy
	var cx: int = from.x
	var cy: int = from.y
	while true:
		points.append(Vector2i(cx, cy))
		if cx == to.x and cy == to.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return points

func _rotate_selection() -> void:
	if not _has_selection:
		return
	for ty in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for tx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			var bid: int = WorldManager.get_tile(tx, ty)
			if bid == 0:
				continue
			if GameState.is_slope(bid):
				if bid >= 2040:
					var rel: int = bid - 2040
					var block_group: int = (rel / 8) * 8
					var sub: int = rel % 8
					var orient: int = sub / 2
					var half_side: int = sub % 2
					orient = (orient + 1) % 4
					WorldManager.set_fg_tile(tx, ty, 2040 + block_group + orient * 2 + half_side)
				else:
					var rel: int = bid - 2000
					var block_group: int = (rel / 4) * 4
					var orient: int = rel % 4
					orient = (orient + 1) % 4
					WorldManager.set_fg_tile(tx, ty, 2000 + block_group + orient)
			else:
				# Regular blocks: replace with current selected block
				WorldManager.set_fg_tile(tx, ty, GameState.selected_block_id)
	queue_redraw()

func _rotate_group_90() -> void:
	# Rotate the entire selection 90° clockwise: blocks physically move positions
	if not _has_selection:
		return
	var sx: int = _selection.position.x
	var sy: int = _selection.position.y
	var w: int = _selection.size.x
	var h: int = _selection.size.y
	var cx: float = sx + w / 2.0
	var cy: float = sy + h / 2.0

	# Read all blocks in selection
	var blocks: Array = []
	for ty in range(sy, sy + h):
		for tx in range(sx, sx + w):
			var bid: int = WorldManager.get_tile(tx, ty)
			var rot: int = WorldManager.get_rotation(tx, ty)
			if bid != 0:
				blocks.append({"x": tx, "y": ty, "id": bid, "rot": rot})

	# Clear old positions
	for b in blocks:
		WorldManager.set_fg_tile(b.x, b.y, 0)
		WorldManager.set_rotation(b.x, b.y, 0)

	# Place at new rotated positions (90° CW around center)
	for b in blocks:
		var rel_x: float = float(b.x) - cx + 0.5
		var rel_y: float = float(b.y) - cy + 0.5
		# 90° CW: new_x = rel_y, new_y = -rel_x
		var new_x: int = int(floor(cx + rel_y - 0.5))
		var new_y: int = int(floor(cy - rel_x - 0.5))
		if new_x >= 1 and new_x < WorldManager.world_width - 1 and new_y >= 1 and new_y < WorldManager.world_height - 1:
			WorldManager.set_fg_tile(new_x, new_y, b.id)
			WorldManager.set_rotation(new_x, new_y, (b.rot + 90) % 360)

	# Update selection rect to match new dimensions (w/h swap)
	var new_sx: int = int(floor(cx - h / 2.0))
	var new_sy: int = int(floor(cy - w / 2.0))
	_selection = Rect2i(new_sx, new_sy, h, w)
	queue_redraw()

func _apply_move(dx: int, dy: int) -> void:
	if not _has_selection or _move_blocks.is_empty():
		return
	# Clear old positions
	for my in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for mx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			WorldManager.set_fg_tile(mx, my, 0)
			WorldManager.set_rotation(mx, my, 0)
	# Move selection rect
	_selection.position.x += dx
	_selection.position.y += dy
	# Place blocks at new positions
	for b in _move_blocks:
		var nx: int = _selection.position.x + b.rx
		var ny: int = _selection.position.y + b.ry
		if nx >= 1 and nx < WorldManager.world_width - 1 and ny >= 1 and ny < WorldManager.world_height - 1:
			WorldManager.set_fg_tile(nx, ny, b.id)
			WorldManager.set_rotation(nx, ny, b.rot)

func _get_align_sel_center(include_drag: bool = false) -> Vector2:
	# Visual center of the aligned selection box
	# include_drag=false for pivot point (stays fixed), true for visual drawing
	var extra: float = _align_drag_angle if include_drag else 0.0
	var ar: float = deg_to_rad(_align_angle + extra)
	var vgo: Vector2 = _align_origin + Vector2(8, 8) + Vector2(-8, -8).rotated(ar)
	var mn: Vector2 = Vector2(minf(_align_sel_start.x, _align_sel_end.x), minf(_align_sel_start.y, _align_sel_end.y))
	var mx: Vector2 = Vector2(maxf(_align_sel_start.x, _align_sel_end.x) + 1, maxf(_align_sel_start.y, _align_sel_end.y) + 1)
	var c0: Vector2 = vgo + (mn * 16.0).rotated(ar)
	var c2: Vector2 = vgo + (mx * 16.0).rotated(ar)
	return (c0 + c2) / 2.0

func _get_aligned_local(world_pos: Vector2) -> Vector2:
	var rad: float = deg_to_rad(-_align_angle)
	var rel: Vector2 = world_pos - _align_origin
	var local: Vector2 = rel.rotated(rad)
	return Vector2(floor(local.x / 16.0), floor(local.y / 16.0))

func _aligned_local_to_world(local_grid: Vector2) -> Vector2:
	# Convert rotated grid coords back to world position
	var world_local: Vector2 = local_grid * 16.0
	return _align_origin + world_local.rotated(deg_to_rad(_align_angle))

func _delete_aligned_selection() -> void:
	var min_x: float = minf(_align_sel_start.x, _align_sel_end.x)
	var min_y: float = minf(_align_sel_start.y, _align_sel_end.y)
	var max_x: float = maxf(_align_sel_start.x, _align_sel_end.x)
	var max_y: float = maxf(_align_sel_start.y, _align_sel_end.y)
	var rad: float = deg_to_rad(-_align_angle)
	var i: int = WorldManager.free_blocks.size() - 1
	while i >= 0:
		var fb: Dictionary = WorldManager.free_blocks[i]
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		var rel: Vector2 = fc - _align_origin
		var local: Vector2 = rel.rotated(rad) / 16.0
		if local.x >= min_x - 0.5 and local.x <= max_x + 0.5 and local.y >= min_y - 0.5 and local.y <= max_y + 0.5:
			WorldManager.free_blocks.remove_at(i)
		i -= 1
	_align_has_sel = false
	queue_redraw()

func _get_aligned_snap(world_pos: Vector2) -> Vector2:
	var rad: float = deg_to_rad(-_align_angle)
	var rel: Vector2 = world_pos - _align_origin
	var local: Vector2 = rel.rotated(rad)
	local.x = round(local.x / 16.0) * 16.0
	local.y = round(local.y / 16.0) * 16.0
	return _align_origin + local.rotated(-rad)

var _free_originals: Array = []
var _free_center: Vector2 = Vector2.ZERO

func _lift_aligned_to_free(center_pt: Vector2) -> void:
	if _free_originals.size() > 0:
		return
	_free_center = center_pt
	var inv: float = deg_to_rad(-_align_angle)
	var mn: Vector2 = Vector2(minf(_align_sel_start.x, _align_sel_end.x), minf(_align_sel_start.y, _align_sel_end.y))
	var mx: Vector2 = Vector2(maxf(_align_sel_start.x, _align_sel_end.x), maxf(_align_sel_start.y, _align_sel_end.y))
	var to_remove: Array = []
	for i in range(WorldManager.free_blocks.size()):
		var fb: Dictionary = WorldManager.free_blocks[i]
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		var loc: Vector2 = (fc - _align_origin).rotated(inv)
		var gx: float = floor(loc.x / 16.0)
		var gy: float = floor(loc.y / 16.0)
		if gx >= mn.x and gx <= mx.x and gy >= mn.y and gy <= mx.y:
			_free_originals.append({"pos": fb.pos, "id": fb.id, "rot": fb.rotation})
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		WorldManager.free_blocks.remove_at(to_remove[i])
	for orig in _free_originals:
		WorldManager.free_blocks.append({"pos": orig.pos, "id": orig.id, "rotation": orig.rot})

func _lift_to_free() -> void:
	# If already lifted, don't re-lift (blocks already off grid)
	if _free_originals.size() > 0:
		return
	var cx: float = (_selection.position.x + _selection.size.x / 2.0) * 16.0
	var cy: float = (_selection.position.y + _selection.size.y / 2.0) * 16.0
	_free_center = Vector2(cx, cy)
	# Lift grid tiles
	for ty in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for tx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			var bid: int = WorldManager.get_tile(tx, ty)
			if bid != 0:
				var pos: Vector2 = Vector2(tx * 16.0, ty * 16.0)
				_free_originals.append({"pos": pos, "id": bid, "rot": 0.0})
				WorldManager.free_blocks.append({"pos": pos, "id": bid, "rotation": 0.0})
				WorldManager.set_fg_tile(tx, ty, 0)
				WorldManager.set_rotation(tx, ty, 0)
	# Also grab existing free blocks within selection area
	var sel_rect: Rect2 = Rect2(cx - (_selection.size.x / 2.0) * 16.0, cy - (_selection.size.y / 2.0) * 16.0,
		_selection.size.x * 16.0, _selection.size.y * 16.0)
	var to_remove: Array = []
	for i in range(WorldManager.free_blocks.size()):
		var fb: Dictionary = WorldManager.free_blocks[i]
		if sel_rect.has_point(fb.pos + Vector2(8, 8)):
			# Check it wasn't just added above (grid tiles)
			var is_new: bool = false
			for orig in _free_originals:
				if orig.pos.distance_to(fb.pos) < 1.0 and orig.id == fb.id and orig.rot == 0.0:
					is_new = true
					break
			if not is_new:
				_free_originals.append({"pos": fb.pos, "id": fb.id, "rot": fb.rotation})
				to_remove.append(i)
	# Remove grabbed free blocks (they'll be re-added by _rotate_free_blocks)
	for i in range(to_remove.size() - 1, -1, -1):
		WorldManager.free_blocks.remove_at(to_remove[i])
	# Re-add them at current positions (rotation 0 relative to group)
	for orig in _free_originals:
		if orig.rot != 0.0:
			WorldManager.free_blocks.append({"pos": orig.pos, "id": orig.id, "rotation": orig.rot})

func _rotate_free_blocks(angle_deg: float) -> void:
	var rad: float = deg_to_rad(angle_deg)
	# Remove only the blocks from this selection (keep previously placed free blocks)
	# Current selection blocks are at the END of the array (_free_originals.size() count)
	WorldManager.free_blocks.resize(WorldManager.free_blocks.size() - _free_originals.size())

	# Collect ALL corners of ALL blocks in world space
	var all_corners: Array = []
	for orig in _free_originals:
		var rel: Vector2 = orig.pos + Vector2(8, 8) - _free_center
		var rotated_pos: Vector2 = rel.rotated(rad)
		var new_pos: Vector2 = _free_center + rotated_pos - Vector2(8, 8)
		WorldManager.free_blocks.append({"pos": new_pos, "id": orig.id, "rotation": orig.rot + angle_deg})
		# 4 corners of this block
		var c: Vector2 = new_pos + Vector2(8, 8)
		all_corners.append(c + Vector2(-8, -8).rotated(rad))
		all_corners.append(c + Vector2(8, -8).rotated(rad))
		all_corners.append(c + Vector2(8, 8).rotated(rad))
		all_corners.append(c + Vector2(-8, 8).rotated(rad))

	# Bounding rect in local space
	var min_lx: float = INF
	var min_ly: float = INF
	var max_lx: float = -INF
	var max_ly: float = -INF
	for orig in _free_originals:
		var rel: Vector2 = orig.pos - _free_center + Vector2(8, 8)
		min_lx = minf(min_lx, rel.x - 8)
		min_ly = minf(min_ly, rel.y - 8)
		max_lx = maxf(max_lx, rel.x + 8)
		max_ly = maxf(max_ly, rel.y + 8)

	# 4 corners rotated to world
	var tl: Vector2 = _free_center + Vector2(min_lx, min_ly).rotated(rad)
	var tr: Vector2 = _free_center + Vector2(max_lx, min_ly).rotated(rad)
	var bl: Vector2 = _free_center + Vector2(min_lx, max_ly).rotated(rad)
	var br: Vector2 = _free_center + Vector2(max_lx, max_ly).rotated(rad)

	# No L-lines needed - collision is solid rectangle in _collides_px
	WorldManager.free_blocks_changed.emit()

func _convex_hull(points: Array) -> Array:
	# Gift wrapping (Jarvis march) for convex hull - returns CCW ordered points
	if points.size() < 3:
		return points
	# Find leftmost point
	var start: int = 0
	for i in range(1, points.size()):
		if points[i].x < points[start].x or (points[i].x == points[start].x and points[i].y < points[start].y):
			start = i
	var hull: Array = []
	var current: int = start
	var count: int = 0
	while count < 100:  # Safety limit
		hull.append(points[current])
		var next: int = 0
		for i in range(points.size()):
			if i == current:
				continue
			if next == current:
				next = i
				continue
			var cross: float = (points[i] - points[current]).cross(points[next] - points[current])
			if cross > 0:
				next = i
			elif cross == 0:
				# Collinear: pick the farther point
				if points[current].distance_squared_to(points[i]) > points[current].distance_squared_to(points[next]):
					next = i
		current = next
		count += 1
		if current == start:
			break
	return hull

func _get_rotated_corners(pos: Vector2, rad: float) -> Array:
	var center: Vector2 = pos + Vector2(8, 8)
	var offsets: Array = [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]
	var corners: Array = []
	for off in offsets:
		corners.append(center + off.rotated(rad))
	return corners  # [top-left, top-right, bottom-right, bottom-left]

func _remove_free_block_lines() -> void:
	var i: int = WorldManager.lines.size() - 1
	while i >= 0:
		if WorldManager.lines[i].has("_free"):
			WorldManager.lines.remove_at(i)
		i -= 1

func _clear_selection() -> void:
	if not _has_selection:
		return
	# Clear grid tiles in selection
	for ty in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for tx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			WorldManager.set_fg_tile(tx, ty, 0)
			WorldManager.set_bg_tile(tx, ty, 0)
	# Also remove free blocks within selection area
	var sel_rect: Rect2 = Rect2(
		_selection.position.x * 16.0, _selection.position.y * 16.0,
		_selection.size.x * 16.0, _selection.size.y * 16.0)
	var i: int = WorldManager.free_blocks.size() - 1
	while i >= 0:
		var fb: Dictionary = WorldManager.free_blocks[i]
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		if sel_rect.has_point(fc):
			WorldManager.free_blocks.remove_at(i)
		i -= 1
	_deselect()
	queue_redraw()

func _deselect() -> void:
	_has_selection = false
	_free_originals.clear()
	# Don't clear free_blocks - they should persist in the world!
