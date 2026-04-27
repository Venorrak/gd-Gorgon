@tool
class_name GraphCircuitLine extends GraphLine


enum ConnectionMode { OFF, MERGED, SEPARATE }
enum EndPointStyle { NONE, CIRCLE, SQUARE, SCHEMATIC_ARROW, RHOMBUS }
enum FadeMode { FADE_AT_ENDS, FADE_AT_CENTER, UNIFORM }


#region Settings
@export var connection_mode: ConnectionMode = ConnectionMode.MERGED:
	set(v): connection_mode = v; emit_changed()

@export var margin: float = 12.0:          ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var separate_stride: float = 12.0: ## Distance between parallel lines when `ConnectionMode.SEPARATE` is used.
	set(v): separate_stride = v; emit_changed()
@export var connection_color: Color = Color(0.2, 0.8, 0.4, 1.0):
	set(v): connection_color = v; emit_changed()
@export var connection_width: float = 2.0:
	set(v): connection_width = v; emit_changed()

@export_group("Endpoints")
@export var start_style: EndPointStyle = EndPointStyle.SQUARE:
	set(v): start_style = v; emit_changed()
@export var end_style: EndPointStyle = EndPointStyle.RHOMBUS:
	set(v): end_style = v; emit_changed()
@export var shape_size: float = 8.0:  ## Size of the endpoint shapes (Circles, Squares).
	set(v): shape_size = v; emit_changed()
@export var arrow_size: float = 10.0: ## Size of the directional indicators (Arrows, Rhombuses).
	set(v): arrow_size = v; emit_changed()

@export_group("Animation & Rail")
@export var animate_flow: bool = true:
	set(v): animate_flow = v; emit_changed()
@export var flow_speed: float = 1.5:
	set(v): flow_speed = v; emit_changed()
@export var segment_length: float = 24.0: ## Distance between repeating rail segments.
	set(v): segment_length = v; emit_changed()
@export var fade_mode: FadeMode = FadeMode.FADE_AT_ENDS:
	set(v): fade_mode = v; emit_changed()
@export var fade_distance: float = 50.0:  ## Distance over which the fading effect is applied.
	set(v): fade_distance = v; emit_changed()
#endregion


var _cached_segment: PackedVector2Array
var _cached_rhombus: PackedVector2Array
var _last_shape_size: float = -1.0
var _last_arrow_size: float = -1.0

func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true) or connection_mode == ConnectionMode.OFF: return
	
	if _last_shape_size != shape_size or _last_arrow_size != arrow_size: _update_caches()
	
	var alpha = context.get("alpha", 1.0)
	var final_color = (context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else connection_color)
	final_color.a *= alpha
	
	var delta = end - start
	var total_length = delta.length()
	if total_length <= margin * 2.0: return
	
	var direction = delta / total_length
	var ortho = direction.orthogonal()
	var angle = direction.angle()
	
	var anchor_start = start + direction * margin
	var anchor_end = end - direction * margin
	
	var is_mutual = context.get("conn_mutual", false)
	var is_primary = context.get("is_primary", true)
	if connection_mode == ConnectionMode.MERGED:
		if is_mutual and not is_primary: return
	elif connection_mode == ConnectionMode.SEPARATE and is_mutual:
		anchor_start += ortho * separate_stride
		anchor_end += ortho * separate_stride
	
	var active_start_style = start_style
	var active_end_style = end_style
	if is_mutual and connection_mode == ConnectionMode.MERGED: active_start_style = end_style
	
	var line_start = _get_adjusted_position(anchor_start, direction, active_start_style, 1.0)
	var line_end = _get_adjusted_position(anchor_end, direction, active_end_style, -1.0)
	
	canvas.draw_line(line_start, line_end, final_color, connection_width)
	
	_draw_optimized_rail(canvas, line_start, line_end, angle, final_color)
	
	_draw_endpoint_opt(canvas, anchor_start, angle + PI, active_start_style, final_color)
	_draw_endpoint_opt(canvas, anchor_end, angle, active_end_style, final_color)

func _update_caches():
	_last_shape_size = shape_size
	_last_arrow_size = arrow_size
	
	var h = shape_size * 0.4
	_cached_segment = PackedVector2Array([Vector2(h, 0), Vector2(0, h), Vector2(-h, 0), Vector2(0, -h)])
	
	var hl = arrow_size * 0.5
	var hw = arrow_size * 0.4
	_cached_rhombus = PackedVector2Array([Vector2(0, 0), Vector2(-hl, hw), Vector2(-arrow_size, 0), Vector2(-hl, -hw)])

func _draw_optimized_rail(canvas: Control, start_pos: Vector2, end_pos: Vector2, angle: float, color: Color):
	var diff = end_pos - start_pos
	var total_len = diff.length()
	if total_len < segment_length: return
	
	var dir = diff / total_len
	var offset = 0.0
	if animate_flow and not Engine.is_editor_hint():
		offset = fmod(Time.get_ticks_msec() * 0.001 * flow_speed * segment_length, segment_length)
	
	var steps = int((total_len - offset) / segment_length)
	for i in range(steps + 1):
		var d = i * segment_length + offset
		var t = 1.0
		
		if fade_mode == FadeMode.FADE_AT_ENDS:
			t = min(d / fade_distance, (total_len - d) / fade_distance)
		elif fade_mode == FadeMode.FADE_AT_CENTER:
			t = abs(d - total_len * 0.5) / fade_distance
		
		t = clamp(t, 0.0, 1.0)
		if t < 0.05: continue
		
		var p = start_pos + dir * d
		var c = color
		c.a *= t
		
		canvas.draw_set_transform(p, angle, Vector2.ONE)
		canvas.draw_colored_polygon(_cached_segment, c)
	
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_endpoint_opt(canvas: Control, pos: Vector2, angle: float, style: EndPointStyle, color: Color):
	canvas.draw_set_transform(pos, angle, Vector2.ONE)
	match style:
		EndPointStyle.CIRCLE:
			canvas.draw_arc(Vector2.ZERO, shape_size * 0.5, 0, TAU, 16, color, connection_width, true)
		EndPointStyle.SQUARE:
			var s = shape_size
			canvas.draw_rect(Rect2(-s*0.5, -s*0.5, s, s), color)
		EndPointStyle.SCHEMATIC_ARROW:
			var asz = arrow_size
			canvas.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(-asz, asz*0.6), Vector2(-asz, -asz*0.6)]), color)
		EndPointStyle.RHOMBUS:
			canvas.draw_colored_polygon(_cached_rhombus, color)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _get_adjusted_position(base_pos: Vector2, direction: Vector2, style: EndPointStyle, side: float) -> Vector2:
	var d = 0.0
	if style == EndPointStyle.SCHEMATIC_ARROW or style == EndPointStyle.RHOMBUS: d = arrow_size * 0.9
	elif style == EndPointStyle.CIRCLE or style == EndPointStyle.SQUARE: d = shape_size * 0.5
	return base_pos + direction * (d * side)
