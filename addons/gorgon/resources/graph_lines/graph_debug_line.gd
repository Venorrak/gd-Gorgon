@tool
class_name GraphDebugLine extends GraphLine


enum ConnectionMode { OFF, MERGED, SEPARATE }
enum EndPointStyle { NONE, CIRCLE, ARROW }


#region Settings
@export var connection_mode: ConnectionMode = ConnectionMode.MERGED:
	set(v): connection_mode = v; emit_changed()
@export var navigation_mode: ConnectionMode = ConnectionMode.MERGED:
	set(v): navigation_mode = v; emit_changed()

@export var margin: float = 12.0:          ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var parallel_spacing: float = 8.0: ## Distance between Connection and Navigation lines when both are active.
	set(v): parallel_spacing = v; emit_changed()
@export var separate_stride: float = 12.0: ## Distance between parallel lines when [code]ConnectionMode.SEPARATE[/code] is used.
	set(v): separate_stride = v; emit_changed()

@export_group("Connection Style")
@export var connection_color: Color = Color(0.85, 0.85, 0.85, 1.0):
	set(v): connection_color = v; emit_changed()
@export var connection_width: float = 4.0:
	set(v): connection_width = v; emit_changed()

@export var conn_start_style: EndPointStyle = EndPointStyle.CIRCLE:
	set(v): conn_start_style = v; emit_changed()
@export var conn_end_style: EndPointStyle = EndPointStyle.ARROW:
	set(v): conn_end_style = v; emit_changed()
@export var conn_endpoint_radius: float = 5.0:
	set(v): conn_endpoint_radius = v; emit_changed()
@export var conn_arrow_len: float = 20.0:
	set(v): conn_arrow_len = v; _conn_arrow_dirty = true; emit_changed()
@export var conn_arrow_width: float = 16.0:
	set(v): conn_arrow_width = v; _conn_arrow_dirty = true; emit_changed()
@export var conn_corner_radius: float = 2.0:
	set(v): conn_corner_radius = v; _conn_arrow_dirty = true; emit_changed()

@export_group("Navigation Style")
@export var navigation_color: Color = Color(0.65, 0.65, 0.65, 1.0):
	set(v): navigation_color = v; emit_changed()
@export var navigation_width: float = 2.0:
	set(v): navigation_width = v; emit_changed()

@export var dot_spacing: float = 12.0:
	set(v): dot_spacing = v; emit_changed()
@export var nav_start_style: EndPointStyle = EndPointStyle.NONE:
	set(v): nav_start_style = v; emit_changed()
@export var nav_end_style: EndPointStyle = EndPointStyle.CIRCLE:
	set(v): nav_end_style = v; emit_changed()
@export var nav_endpoint_radius: float = 3.0:
	set(v): nav_endpoint_radius = v; emit_changed()
@export var nav_arrow_len: float = 12.0:
	set(v): nav_arrow_len = v; _nav_arrow_dirty = true; emit_changed()
@export var nav_arrow_width: float = 10.0:
	set(v): nav_arrow_width = v; _nav_arrow_dirty = true; emit_changed()
@export var nav_corner_radius: float = 1.0:
	set(v): nav_corner_radius = v; _nav_arrow_dirty = true; emit_changed()
#endregion


#region Arrow Cache
var _cached_conn_arrow:   PackedVector2Array
var _cached_conn_outline: PackedVector2Array
var _conn_arrow_dirty: bool = true

var _cached_nav_arrow:   PackedVector2Array
var _cached_nav_outline: PackedVector2Array
var _nav_arrow_dirty: bool = true
#endregion


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	var has_conn: bool = context.get("connection", true)
	var has_nav:  bool = context.get("navigation", false)
	var is_conn_mutual: bool = context.get("conn_mutual", false)
	var is_nav_mutual:  bool = context.get("nav_mutual",  false)
	var is_primary: bool = context.get("is_primary", true)
	var alpha: float = context.get("alpha", 1.0)
	var highlight: bool = context.get("highlighted", false)
	var high_color: Color = context.get("highlight_color", Color.WHITE)
	
	var pair_has_nav: bool = context.get("pair_has_nav", false)
	var pair_has_conn: bool = context.get("pair_has_conn", false)
	
	## Геометрия
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2 = delta_vector / total_length
	var ortho: Vector2 = direction.orthogonal()
	var anchor_start: Vector2 = start + direction * margin
	var anchor_end: Vector2   = end   - direction * margin
	
	var do_conn: bool = has_conn and connection_mode != ConnectionMode.OFF
	var do_nav:  bool = has_nav  and navigation_mode != ConnectionMode.OFF
	
	var connection_offset: Vector2 = Vector2.ZERO
	var navigation_offset: Vector2 = Vector2.ZERO
	
	if pair_has_conn and pair_has_nav:
		var stable_ortho = ortho if is_primary else -ortho
		connection_offset = -stable_ortho * parallel_spacing
		navigation_offset =  stable_ortho * parallel_spacing
	
	## Соединения
	if do_conn:
		var color: Color = high_color if highlight else connection_color
		color.a *= alpha
		var active_start_style := conn_start_style
		var active_end_style   := conn_end_style
		
		var render_start := anchor_start + connection_offset
		var render_end   := anchor_end   + connection_offset
		var should_draw := true
		
		if connection_mode == ConnectionMode.MERGED:
			if is_conn_mutual:
				if is_primary:
					active_start_style = conn_end_style
					active_end_style   = conn_end_style
				else:
					should_draw = false
		elif connection_mode == ConnectionMode.SEPARATE and is_conn_mutual:
			var side := 1.0 if is_primary else -1.0
			render_start += ortho * (separate_stride * side)
			render_end   += ortho * (separate_stride * side)
		
		if should_draw:
			_draw_body_solid(canvas, render_start, render_end, direction, color, active_start_style, active_end_style)
	
	## Навигация
	if do_nav:
		var color: Color = navigation_color
		color.a *= alpha
		var active_start_style := nav_start_style
		var active_end_style   := nav_end_style
		
		var render_start := anchor_start + navigation_offset
		var render_end   := anchor_end   + navigation_offset
		var should_draw := true
		
		if navigation_mode == ConnectionMode.MERGED:
			if is_nav_mutual:
				if is_primary:
					active_start_style = nav_end_style
					active_end_style   = nav_end_style
				else:
					should_draw = false
		elif navigation_mode == ConnectionMode.SEPARATE and is_nav_mutual:
			var side := 1.0 if is_primary else -1.0
			render_start += ortho * (separate_stride * side)
			render_end   += ortho * (separate_stride * side)
		
		if should_draw:
			_draw_body_dotted(canvas, render_start, render_end, direction, color, active_start_style, active_end_style)


#region Draw Bodies
func _draw_body_solid(canvas: Control, start_pos: Vector2, end_pos: Vector2, direction: Vector2, color: Color, p_start_style: EndPointStyle, p_end_style: EndPointStyle) -> void:
	var line_start := start_pos
	var line_end   := end_pos
	
	if p_start_style == EndPointStyle.ARROW: line_start += direction * (conn_arrow_len * 0.2)
	if p_end_style   == EndPointStyle.ARROW: line_end   -= direction * (conn_arrow_len * 0.2)
	
	if (line_end - line_start).dot(direction) > 0: 
		canvas.draw_line(line_start, line_end, color, connection_width, false)
	
	_draw_endpoint_conn(canvas, start_pos, -direction, p_start_style, color)
	_draw_endpoint_conn(canvas, end_pos,    direction, p_end_style,   color)


func _draw_body_dotted(canvas: Control, start_pos: Vector2, end_pos: Vector2, direction: Vector2, color: Color, p_start_style: EndPointStyle, p_end_style: EndPointStyle) -> void:
	var body_length := (end_pos - start_pos).length()
	var dot_r := navigation_width * 0.5

	## Точный подсчёт вместо range(1000) + break
	var hide_start := _nav_hide_distance(p_start_style)
	var hide_end   := _nav_hide_distance(p_end_style)
	var half := body_length * 0.5
	var steps_fwd := int((half - hide_end)   / dot_spacing)
	var steps_bwd := int((half - hide_start) / dot_spacing)
	var center := start_pos + direction * half
	
	for i in range(steps_fwd + 1): canvas.draw_circle(center + direction * (i * dot_spacing), dot_r, color)
	for i in range(1, steps_bwd + 1): canvas.draw_circle(center - direction * (i * dot_spacing), dot_r, color)
	
	_draw_endpoint_nav(canvas, start_pos, -direction, p_start_style, color)
	_draw_endpoint_nav(canvas, end_pos,    direction, p_end_style,   color)


func _nav_hide_distance(style: EndPointStyle) -> float:
	match style:
		EndPointStyle.CIRCLE: return nav_endpoint_radius
		EndPointStyle.ARROW:  return nav_arrow_len * 0.7
	return 0.0
#endregion


#region Endpoints
func _draw_endpoint_conn(canvas: Control, pos: Vector2, direction: Vector2, style: EndPointStyle, color: Color) -> void:
	match style:
		EndPointStyle.CIRCLE:
			canvas.draw_circle(pos, conn_endpoint_radius, color)
		EndPointStyle.ARROW:
			if _conn_arrow_dirty or _cached_conn_arrow.is_empty(): _rebuild_conn_arrow()
			canvas.draw_set_transform(pos, direction.angle(), Vector2.ONE)
			canvas.draw_colored_polygon(_cached_conn_arrow, color)
			canvas.draw_polyline(_cached_conn_outline, color, 1.0, false)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_endpoint_nav(canvas: Control, pos: Vector2, direction: Vector2, style: EndPointStyle, color: Color) -> void:
	match style:
		EndPointStyle.CIRCLE:
			canvas.draw_circle(pos, nav_endpoint_radius, color)
		EndPointStyle.ARROW:
			if _nav_arrow_dirty or _cached_nav_arrow.is_empty(): _rebuild_nav_arrow()
			canvas.draw_set_transform(pos, direction.angle(), Vector2.ONE)
			canvas.draw_colored_polygon(_cached_nav_arrow, color)
			canvas.draw_polyline(_cached_nav_outline, color, 1.0, false)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
#endregion


#region Arrow Cache
func _rebuild_conn_arrow() -> void:
	_conn_arrow_dirty = false
	_cached_conn_arrow = _generate_arrow_polygon(conn_arrow_len, conn_arrow_width, conn_corner_radius)
	_cached_conn_outline = _cached_conn_arrow.duplicate()
	_cached_conn_outline.append(_cached_conn_outline[0])

func _rebuild_nav_arrow() -> void:
	_nav_arrow_dirty = false
	_cached_nav_arrow = _generate_arrow_polygon(nav_arrow_len, nav_arrow_width, nav_corner_radius)
	_cached_nav_outline = _cached_nav_arrow.duplicate()
	_cached_nav_outline.append(_cached_nav_outline[0])

## Generates a polygon arrow with rounded corners (tip at 0,0, pointing to the right).
func _generate_arrow_polygon(length: float, width: float, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	
	var p1 := Vector2.ZERO
	var p2 := Vector2(-length,  width * 0.5)
	var p3 := Vector2(-length, -width * 0.5)
	
	if radius <= 0.0:
		result.append_array([p1, p2, p3])
		return result
	
	var verts := [p1, p2, p3]
	const STEPS := 8
	
	for i in range(3):
		var prev = verts[(i - 1 + 3) % 3]
		var curr = verts[i]
		var next = verts[(i + 1) % 3]
		
		var dir_prev = (prev - curr).normalized()
		var dir_next = (next - curr).normalized()
		var angle = abs(dir_prev.angle_to(dir_next))
		
		if angle < 0.01 or angle >= PI - 0.01:
			result.append(curr)
			continue
		
		var max_r = min(curr.distance_to(prev), curr.distance_to(next)) * 0.45 * tan(angle / 2.0)
		var r = min(radius, max_r)
		var d_center = r / sin(angle / 2.0)
		var bisector = (dir_prev + dir_next).normalized()
		var center = curr + bisector * d_center
		var d_tan = r / tan(angle / 2.0)
		var start_p = curr + dir_prev * d_tan
		var end_p   = curr + dir_next * d_tan
		var a_start = (start_p - center).angle()
		var a_end   = (end_p   - center).angle()
		var a_diff  = wrapf(a_end - a_start, -PI, PI)
	
		for s in range(STEPS + 1):
			var a = a_start + a_diff * (float(s) / STEPS)
			result.append(center + Vector2(cos(a), sin(a)) * r)
	
	return result
#endregion
