@tool
class_name GraphSoftLine extends GraphLine


enum ConnectionMode { OFF, MERGED, SEPARATE }
enum EndPointStyle { NONE, CIRCLE, ARROW }

var _cached_arrow: PackedVector2Array
var _last_arrow_length: float
var _last_arrow_width: float
var _last_corner_radius: float

#region Settings
@export var connection_mode: ConnectionMode = ConnectionMode.MERGED:
	set(v): connection_mode = v; emit_changed()


@export var margin: float = 12.0:          ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var separate_stride: float = 12.0: ## Distance between parallel lines when [code]ConnectionMode.SEPARATE[/code] is used.
	set(v): separate_stride = v; emit_changed()

@export var connection_color: Color = Color(0.85, 0.85, 0.85, 1.0):
	set(v): connection_color = v; emit_changed()
@export var connection_width: float = 4.0:
	set(v): connection_width = v; emit_changed()

@export_group("Endpoints")
@export var start_style: EndPointStyle = EndPointStyle.CIRCLE:
	set(v): start_style = v; emit_changed()
@export var end_style: EndPointStyle = EndPointStyle.ARROW:
	set(v): end_style = v; emit_changed()
@export var endpoint_radius: float = 6.0:
	set(v): endpoint_radius = v; emit_changed()

@export_group("Arrows")
@export var arrow_length: float = 20.0:
	set(v): arrow_length = v; emit_changed()
@export var arrow_width: float = 16.0:
	set(v): arrow_width = v; emit_changed()
@export var corner_radius: float = 2.0:
	set(v): corner_radius = v; emit_changed()
#endregion


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
				active_end_style = end_style
			else: 
				return
	elif connection_mode == ConnectionMode.SEPARATE and is_mutual:
		anchor_start += ortho * separate_stride
		anchor_end += ortho * separate_stride
	
	_draw_solid_body(canvas, anchor_start, anchor_end, direction, ortho, final_color, active_start_style, active_end_style)


func _draw_solid_body(canvas: Control, start_pos: Vector2, end_pos: Vector2, direction: Vector2, ortho: Vector2, color: Color, start_style: EndPointStyle, end_style: EndPointStyle) -> void:
	var line_start: Vector2 = start_pos
	var line_end: Vector2 = end_pos
	
	if start_style == EndPointStyle.ARROW: line_start += direction * (arrow_length * 0.2)
	if end_style == EndPointStyle.ARROW: line_end -= direction * (arrow_length * 0.2)
	
	if (line_end - line_start).dot(direction) > 0: canvas.draw_line(line_start, line_end, color, connection_width, false)
	
	_draw_endpoint(canvas, start_pos, -direction, -ortho, start_style, color)
	_draw_endpoint(canvas, end_pos, direction, ortho, end_style, color)

func _draw_endpoint(canvas: Control, pos: Vector2, direction: Vector2, ortho: Vector2, style: EndPointStyle, color: Color) -> void:
	match style:
		EndPointStyle.CIRCLE: canvas.draw_circle(pos, endpoint_radius, color)
		EndPointStyle.ARROW: _draw_arrow_head(canvas, pos, direction, ortho, color)

func _draw_arrow_head(canvas: Control, tip_pos: Vector2, direction: Vector2, ortho: Vector2, color: Color) -> void:
	if _cached_arrow.is_empty() or _last_arrow_length != arrow_length or _last_arrow_width != arrow_width or _last_corner_radius != corner_radius:
		_generate_arrow_cache()
	
	canvas.draw_set_transform(tip_pos, direction.angle(), Vector2.ONE)
	
	canvas.draw_colored_polygon(_cached_arrow, color)
	
	var outline = _cached_arrow.duplicate()
	outline.append(outline[0])
	canvas.draw_polyline(outline, color, 1.0, false)
	
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _generate_arrow_cache() -> void:
	_last_arrow_length = arrow_length
	_last_arrow_width = arrow_width
	_last_corner_radius = corner_radius
	_cached_arrow.clear()
	
	var p1 := Vector2.ZERO
	var p2 := Vector2(-arrow_length, arrow_width * 0.5)
	var p3 := Vector2(-arrow_length, -arrow_width * 0.5)
	
	if corner_radius <= 0.0:
		_cached_arrow.append_array([p1, p2, p3])
		return
	
	var verts = [p1, p2, p3]
	var count = 3
	const STEPS = 8
	
	for i in range(count):
		var prev = verts[(i - 1 + count) % count]
		var curr = verts[i]
		var next = verts[(i + 1) % count]
		
		var dir_prev = (prev - curr).normalized()
		var dir_next = (next - curr).normalized()
		
		var angle = abs(dir_prev.angle_to(dir_next))
		
		if angle < 0.01 or angle >= PI - 0.01:
			_cached_arrow.append(curr)
			continue
		
		var max_r = min(curr.distance_to(prev), curr.distance_to(next)) * 0.45 * tan(angle / 2.0)
		var r = min(corner_radius, max_r)
		
		var d_center = r / sin(angle / 2.0)
		var bisector = (dir_prev + dir_next).normalized()
		var center = curr + bisector * d_center
		
		var d_tan = r / tan(angle / 2.0)
		var start_p = curr + dir_prev * d_tan
		var end_p = curr + dir_next * d_tan
		
		var a_start = (start_p - center).angle()
		var a_end = (end_p - center).angle()
		
		var a_diff = wrapf(a_end - a_start, -PI, PI)
		
		for s in range(STEPS + 1):
			var a = a_start + a_diff * (float(s) / STEPS)
			_cached_arrow.append(center + Vector2(cos(a), sin(a)) * r)
