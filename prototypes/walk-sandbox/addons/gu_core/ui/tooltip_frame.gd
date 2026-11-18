class_name TooltipFrame
extends RefCounted
## Delayed tooltip placement that flips inward when the anchor sits on a screen edge.

var delay: float = 0.15
var size: Vector2 = Vector2(160, 48)
var shown: bool = false
var position: Vector2 = Vector2.ZERO

var _text: String = ""
var _anchor: Rect2 = Rect2()
var _viewport: Vector2 = Vector2(1280, 720)
var _wait: float = 0.0


func request(text: String, anchor: Rect2, viewport_size: Vector2) -> void:
	_text = text
	_anchor = anchor
	_viewport = viewport_size
	_wait = 0.0
	shown = false


func advance(delta: float) -> void:
	if _text == "":
		return
	_wait += delta
	if _wait < delay:
		return
	shown = true
	var x := _anchor.position.x
	var y := _anchor.end.y + 6.0
	if x + size.x > _viewport.x:
		x = _anchor.position.x - size.x
	if y + size.y > _viewport.y:
		y = _anchor.position.y - size.y - 6.0
	position = Vector2(x, y)


func get_text() -> String:
	return _text if shown else ""
