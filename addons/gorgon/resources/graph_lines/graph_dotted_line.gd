@tool
class_name GraphDottedLine extends GraphLine


enum ConnectionMode { OFF, MERGED, SEPARATE }
enum EndPointStyle { NONE, CIRCLE, ARROW }


#region Settings
@export var connection_mode: ConnectionMode = ConnectionMode.MERGED:
	set(v): connection_mode = v; emit_changed()

@export var margin: float = 12.0:          ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var separate_stride: float = 12.0: ## Distance between parallel lines when [code]ConnectionMode.SEPARATE[/code] is used.
	set(v): separate_stride = v; emit_changed()
@export var dot_spacing: float = 14.0:     ## Distance between local dots.
	set(v): dot_spacing = v; emit_changed()
@export var dot_radius: float = 2.0:
	set(v): dot_radius = v; emit_changed()

@export var connection_color: Color = Color(0.85, 0.85, 0.85, 1.0):
	set(v): connection_color = v; emit_changed()

@export_group("Endpoints")
@export var start_style: EndPointStyle = EndPointStyle.CIRCLE:
	set(v): start_style = v; emit_changed()
@export var end_style: EndPointStyle = EndPointStyle.ARROW:
	set(v): end_style = v; emit_changed()
@export var endpoint_radius: float = 5.0:
	set(v): endpoint_radius = v; emit_changed()

@export_group("Arrows")
@export var arrow_length: float = 16.0:
	set(v): arrow_length = v; _arrow_dirty = true; emit_changed()
@export var arrow_width: float = 12.0:
	set(v): arrow_width = v; _arrow_dirty = true; emit_changed()
@export var corner_radius: float = 2.0:
	set(v): corner_radius = v; _arrow_dirty = true; emit_changed()
#endregion


## [Arrow Cache] Pre-built polygon, rebuilt only when arrow params change.
var _cached_arrow: PackedVector2Array
var _arrow_dirty: bool = true


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true) or connection_mode == ConnectionMode.OFF: return
	
	var is_mutual: bool = context.get("conn_mutual", false)
	var is_primary: bool = context.get("is_primary", true)
	var alpha: float = context.get("alpha", 1.0)
	var final_color: Color = (context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else connection_color)
	final_color.a *= alpha

	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return

	var direction: Vector2 = delta_vector / total_length
	var ortho: Vector2 = direction.orthogonal()

	var anchor_start: Vector2 = start + direction * margin
	var anchor_end: Vector2 = end - direction * margin
	var active_start_style: EndPointStyle = start_style
	var active_end_style: EndPointStyle = end_style

	if connection_mode == ConnectionMode.MERGED:
		if is_mutual:
			if is_primary:
				active_start_style = end_style
				active_end_style   = end_style
			else:
				return
	elif connection_mode == ConnectionMode.SEPARATE and is_mutual:
		anchor_start += ortho * separate_stride
		anchor_end   += ortho * separate_stride
	
	var hide_start := _endpoint_hide_distance(active_start_style)
	var hide_end   := _endpoint_hide_distance(active_end_style)
	
	_draw_dots(canvas, anchor_start, anchor_end, direction, hide_start, hide_end, final_color)
	
	_draw_endpoint(canvas, anchor_start, -direction, -ortho, active_start_style, final_color)
	_draw_endpoint(canvas, anchor_end,    direction,  ortho, active_end_style,   final_color)


## Returns how many pixels from the anchor point should be kept free of dots.
func _endpoint_hide_distance(style: EndPointStyle) -> float:
	match style:
		EndPointStyle.CIRCLE: return endpoint_radius
		EndPointStyle.ARROW:  return arrow_length * 0.7
	return 0.0


## Draws all dots symmetrically from the center outward.
## Pre-calculates exact counts — no magic `range(1000)` with a break.
func _draw_dots(canvas: Control, p_start: Vector2, p_end: Vector2, direction: Vector2, hide_start: float, hide_end: float, color: Color) -> void:
	var line_vec    := p_end - p_start
	var line_length := line_vec.length()
	var half_length := line_length * 0.5
	if dot_spacing <= 0.0 or half_length <= 0.0: return

	var center := p_start + direction * half_length

	var steps_fwd := int((half_length - hide_end)   / dot_spacing)
	var steps_bwd := int((half_length - hide_start) / dot_spacing)

	for i in range(steps_fwd + 1):
		canvas.draw_circle(center + direction * (i * dot_spacing), dot_radius, color)

	for i in range(1, steps_bwd + 1):
		canvas.draw_circle(center - direction * (i * dot_spacing), dot_radius, color)


func _draw_endpoint(canvas: Control, pos: Vector2, direction: Vector2, ortho: Vector2, style: EndPointStyle, color: Color) -> void:
	match style:
		EndPointStyle.CIRCLE: canvas.draw_circle(pos, endpoint_radius, color)
		EndPointStyle.ARROW:  _draw_arrow_head(canvas, pos, direction, color)


## Cached polygon arrow — same rounding algorithm as GraphSoftLine.
## Rebuilds only when arrow_length / arrow_width / corner_radius change.
func _draw_arrow_head(canvas: Control, tip_pos: Vector2, direction: Vector2, color: Color) -> void:
	if _arrow_dirty or _cached_arrow.is_empty(): _generate_arrow_cache()

	canvas.draw_set_transform(tip_pos, direction.angle(), Vector2.ONE)
	canvas.draw_colored_polygon(_cached_arrow, color)

	var outline := _cached_arrow.duplicate()
	outline.append(outline[0])
	canvas.draw_polyline(outline, color, 1.0, false)

	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _generate_arrow_cache() -> void:
	_arrow_dirty = false
	_cached_arrow.clear()

	var p1 := Vector2.ZERO
	var p2 := Vector2(-arrow_length,  arrow_width * 0.5)
	var p3 := Vector2(-arrow_length, -arrow_width * 0.5)

	if corner_radius <= 0.0:
		_cached_arrow.append_array([p1, p2, p3])
		return

	var verts := [p1, p2, p3]
	var count  := 3
	const STEPS := 8

	for i in range(count):
		var prev = verts[(i - 1 + count) % count]
		var curr = verts[i]
		var next = verts[(i + 1) % count]

		var dir_prev = (prev - curr).normalized()
		var dir_next = (next - curr).normalized()
		var angle    = abs(dir_prev.angle_to(dir_next))
		
		if angle < 0.01 or angle >= PI - 0.01: _cached_arrow.append(curr); continue
		
		var max_r    = min(curr.distance_to(prev), curr.distance_to(next)) * 0.45 * tan(angle / 2.0)
		var r        = min(corner_radius, max_r)
		var d_center = r / sin(angle / 2.0)
		var bisector = (dir_prev + dir_next).normalized()
		var center   = curr + bisector * d_center
		var d_tan    = r / tan(angle / 2.0)
		var start_p  = curr + dir_prev * d_tan
		var end_p    = curr + dir_next * d_tan
		var a_start  = (start_p - center).angle()
		var a_end    = (end_p   - center).angle()
		var a_diff   = wrapf(a_end - a_start, -PI, PI)

		for s in range(STEPS + 1):
			var a = a_start + a_diff * (float(s) / STEPS)
			_cached_arrow.append(center + Vector2(cos(a), sin(a)) * r)
