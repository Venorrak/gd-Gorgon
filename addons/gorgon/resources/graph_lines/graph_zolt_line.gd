@tool
class_name GraphZoltLine extends GraphLine


#region Exports
@export var margin: float = 12.0: ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var segment_length: float = 10.0: ## Distance between vertices of the jagged line.
	set(v): segment_length = v; emit_changed()
@export var amplitude: float = 6.0:
	set(v): amplitude = v; emit_changed()
@export var animation_speed: float = 15.0: ## How fast the discharge fluctuations pulse.
	set(v): animation_speed = v; emit_changed()
@export var volt_color: Color = Color(1.0, 0.9, 0.4, 1.0):
	set(v): volt_color = v; emit_changed()
@export var thickness: float = 3.0: ## Overall width of the discharge line.
	set(v): thickness = v; emit_changed()
#endregion


## [Points Cache] Reused each frame — no per-frame allocations.
var _points: PackedVector2Array


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true): return
	
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2 = delta_vector / total_length
	var ortho: Vector2 = direction.orthogonal()
	var anchor_start: Vector2 = start + direction * margin
	var anchor_end: Vector2 = end - direction * margin
	var active_len: float = (anchor_end - anchor_start).length()
	
	var time: float = Time.get_ticks_msec() * 0.001 * animation_speed if not Engine.is_editor_hint() else 0.0
	var final_color: Color = context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else volt_color
	final_color.a *= context.get("alpha", 1.0)
	if final_color.a <= 0.01: return
	
	var segments_count: int = int(active_len / max(segment_length, 1.0)) + 1
	var needed_size: int = segments_count + 1
	
	if _points.size() != needed_size: _points.resize(needed_size)
	
	_points[0] = anchor_start
	_points[segments_count] = anchor_end
	
	for i in range(1, segments_count):
		var progress: float = float(i) / segments_count
		var wave_offset:  float = sin(time + i * 1.5) * amplitude
		var noise_offset: float = cos(time * 0.7 + i * 4.0) * (amplitude * 0.3)
		_points[i] = anchor_start.lerp(anchor_end, progress) + ortho * (wave_offset + noise_offset)
	
	canvas.draw_polyline(_points, final_color, thickness, true)
	
	var core_color := Color(1.0, 1.0, 1.0, final_color.a * 0.8)
	canvas.draw_polyline(_points, core_color, thickness * 0.3, true)
