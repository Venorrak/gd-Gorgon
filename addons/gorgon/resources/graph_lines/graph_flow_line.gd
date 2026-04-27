@tool
class_name GraphFlowLine extends GraphLine


enum FlowStyle { PIPE, PACKETS }
enum PacketShape { CIRCLE, BOX, ARROW, CHEVRON }


#region Settings
@export var flow_style: FlowStyle = FlowStyle.PIPE:
	set(v): flow_style = v; notify_property_list_changed(); emit_changed()
@export var packet_shape: PacketShape = PacketShape.CIRCLE:
	set(v): packet_shape = v; _shape_dirty = true; emit_changed()
@export var packet_stretch: float = 1.0: ## Stretching the figure along its length (1.0 = equilateral)
	set(v): packet_stretch = v; _shape_dirty = true; emit_changed()
@export var margin: float = 12.0: ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()

@export_group("Motion")
@export var speed: float = 2.0:
	set(v): speed = v; emit_changed()
@export var spacing: float = 30.0: ## Distance between elements (space)
	set(v): spacing = v; emit_changed()
@export var item_size: float = 20.0: ## Segment length (for PIPE) or figure size (for PACKETS)
	set(v): item_size = v; _shape_dirty = true; emit_changed()
@export var fade_length: float = 15.0: ## Soft fade-in/fade-out zone at the ends
	set(v): fade_length = v; emit_changed()

@export_group("Visuals")
@export var track_color: Color = Color(0.15, 0.15, 0.15, 0.5):
	set(v): track_color = v; emit_changed()
@export var track_width: float = 4.0:
	set(v): track_width = v; emit_changed()
@export var flow_color: Color = Color(0.0, 0.8, 1.0, 1.0):
	set(v): flow_color = v; emit_changed()
@export var flow_width: float = 3.0:
	set(v): flow_width = v; emit_changed()
#endregion


## [Shape Cache] Pre-built base polygon, rebuilt only when shape params change.
var _cached_shape: PackedVector2Array
var _shape_dirty: bool = true


func _get_property_list() -> Array:
	var props = []
	var packet_usage = PROPERTY_USAGE_DEFAULT if flow_style == FlowStyle.PACKETS else PROPERTY_USAGE_NO_EDITOR
	props.append({ "name": "packet_shape",   "type": TYPE_INT,   "usage": packet_usage, "hint": PROPERTY_HINT_ENUM, "hint_string": "Circle,Box,Arrow,Chevron" })
	props.append({ "name": "packet_stretch", "type": TYPE_FLOAT, "usage": packet_usage })
	return props


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true): return
	
	var alpha: float = context.get("alpha", 1.0)
	var final_track_color: Color = track_color;  final_track_color.a *= alpha
	var final_flow_color:  Color = context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else flow_color
	final_flow_color.a *= alpha
	
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2 = delta_vector / total_length
	var anchor_start: Vector2 = start + direction * margin
	var anchor_end: Vector2   = end   - direction * margin
	var active_len: float = (anchor_end - anchor_start).length()
	
	if final_track_color.a > 0.01:
		canvas.draw_line(anchor_start, anchor_end, final_track_color, track_width, true)
		canvas.draw_circle(anchor_start, track_width * 0.5, final_track_color)
		canvas.draw_circle(anchor_end,   track_width * 0.5, final_track_color)
	
	if final_flow_color.a <= 0.01: return
	
	var full_cycle: float = item_size + spacing
	var time: float = Time.get_ticks_msec() * 0.001 * speed * 40.0 if not Engine.is_editor_hint() else 0.0
	var offset: float = fmod(time, full_cycle)
	var rotation_angle: float = direction.angle()
	var inv_fade: float = 1.0 / max(fade_length, 0.001)
	
	if flow_style == FlowStyle.PACKETS and _shape_dirty: _rebuild_shape_cache()
	
	var current_d: float = offset - full_cycle
	while current_d < active_len:
		var item_center_d: float = current_d + item_size * 0.5
		
		var fade_factor: float = 1.0
		if fade_length > 0.001: fade_factor = clamp(min(item_center_d, active_len - item_center_d) * inv_fade, 0.0, 1.0)
		
		var current_color: Color = final_flow_color
		current_color.a *= fade_factor
		
		if current_color.a > 0.01:
			match flow_style:
				FlowStyle.PIPE:
					_draw_pipe_segment(canvas, anchor_start, direction, current_d, active_len, current_color)
				FlowStyle.PACKETS:
					if item_center_d > -item_size and item_center_d < active_len + item_size:
						var center_pos: Vector2 = anchor_start + direction * item_center_d
						_draw_packet(canvas, center_pos, rotation_angle, current_color)
		
		current_d += full_cycle


func _rebuild_shape_cache() -> void:
	_shape_dirty = false
	var r: float = item_size * 0.5
	match packet_shape:
		PacketShape.BOX:
			_cached_shape = PackedVector2Array([
				Vector2(-r * packet_stretch, -r), Vector2(r * packet_stretch, -r),
				Vector2( r * packet_stretch,  r), Vector2(-r * packet_stretch,  r)
				])
		PacketShape.ARROW:
			_cached_shape = PackedVector2Array([
				Vector2(r * packet_stretch, 0),
				Vector2(-r * packet_stretch, -r),
				Vector2(-r * packet_stretch,  r)
				])
		PacketShape.CHEVRON:
			var bx: float = -r * packet_stretch
			var nx: float =  r * packet_stretch
			var indent: float = r * 0.5
			_cached_shape = PackedVector2Array([
				Vector2(nx, 0), Vector2(bx, -r),
				Vector2(bx + indent, 0), Vector2(bx, r)
				])
		_:
			_cached_shape.clear()


func _draw_pipe_segment(canvas: Control, origin: Vector2, direction: Vector2, current_offset: float, max_length: float, color: Color) -> void:
	var seg_start: float = clamp(current_offset,             0.0, max_length)
	var seg_end:   float = clamp(current_offset + item_size, 0.0, max_length)
	if seg_end <= seg_start: return
	
	var pos_a: Vector2 = origin + direction * seg_start
	var pos_b: Vector2 = origin + direction * seg_end
	canvas.draw_line(pos_a, pos_b, color, flow_width, true)
	
	if seg_end - seg_start > flow_width * 0.5:
		canvas.draw_circle(pos_a, flow_width * 0.5, color)
		canvas.draw_circle(pos_b, flow_width * 0.5, color)


func _draw_packet(canvas: Control, center: Vector2, angle: float, color: Color) -> void:
	if packet_shape == PacketShape.CIRCLE:
		canvas.draw_circle(center, item_size * 0.5, color)
		return
	
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	canvas.draw_colored_polygon(_cached_shape, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
