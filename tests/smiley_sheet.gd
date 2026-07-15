extends Node2D
## Dev utility: renders every EE smiley BIG with its id across 3 pages
## (user://smileys_pageN.png) so enemy faces can be chosen by eye.

var _texs: Array = []
var _page: int = 0
var _shot_t: float = 0.4

func _ready() -> void:
	for i in range(2):
		var t: Texture2D = load("res://assets/sprites/smileys_%d.png" % i) as Texture2D
		if t:
			_texs.append(t)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 1280, 760), Color(0.1, 0.1, 0.14))
	var start: int = _page * 64
	for k in range(64):
		var id: int = start + k
		if id >= 188:
			break
		var chunk: int = id / 157
		var lc: int = id % 157
		if chunk >= _texs.size():
			continue
		var cx: float = float(k % 8) * 158.0 + 14.0
		var cy: float = float(k / 8) * 92.0 + 10.0
		draw_texture_rect_region(_texs[chunk], Rect2(cx, cy, 64, 64), Rect2(lc * 26, 0, 26, 26))
		draw_string(font, Vector2(cx + 70.0, cy + 40.0), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 0.6))


func _process(delta: float) -> void:
	_shot_t -= delta
	if _shot_t <= 0.0:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("user://smileys_page%d.png" % _page)
		print("PAGE %d SAVED" % _page)
		_page += 1
		_shot_t = 0.35
		if _page >= 3:
			get_tree().quit(0)
		queue_redraw()
