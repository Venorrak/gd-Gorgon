@tool
class_name GraphNanoLine extends GraphLine


#region Settings
@export var margin: float = 12.0: ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var base_color: Color = Color(1.0, 0.4, 0.1, 1.0):
	set(v): base_color = v; emit_changed()
@export var line_width: float = 1.5: ## Thickness of the fiber segments.
	set(v): line_width = v; emit_changed()
@export var bloom_scale: float = 2.0: ## Width multiplier for glow effect
	set(v): bloom_scale = v; emit_changed()

@export_group("Glitch & Motion")
@export var speed: float = 1.0:
	set(v): speed = v; emit_changed()
@export var glitch_intensity: float = 2.0: ## Lateral displacement force (jitter)
	set(v): glitch_intensity = v; emit_changed()
@export var segment_min_len: float = 5.0: ## Minimum length of a single segment.
	set(v): segment_min_len = v; emit_changed()
@export var segment_max_len: float = 40.0: ## Maximum length of a single segment.
	set(v): segment_max_len = v; emit_changed()
@export var gap_min_len: float = 5.0: ## Minimum distance between segments.
	set(v): gap_min_len = v; emit_changed()
@export var gap_max_len: float = 20.0: ## Maximum distance between segments.
	set(v): gap_max_len = v; emit_changed()
#endregion


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true): return
	
	var alpha: float = context.get("alpha", 1.0)
	var main_color: Color = context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else base_color
	main_color.a *= alpha
	if main_color.a <= 0.01: return
	
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2 = delta_vector / total_length
	var ortho: Vector2 = direction.orthogonal()
	var anchor_start: Vector2 = start + direction * margin
	var active_len: float = total_length - margin * 2.0
	
	var time: float = Time.get_ticks_msec() * 0.001
	var do_bloom: bool = bloom_scale > 1.0
	var do_glitch: bool = glitch_intensity > 0.01
	var inv_pi: float = 1.0 / active_len
	
	var current_d: float = 0.0
	var segment_index: int = 0
	
	while current_d < active_len:
		segment_index += 1
		var seed_val: float = segment_index * 13.0
		var seg_len: float = lerp(segment_min_len, segment_max_len, _pseudo_rand(seed_val))
		var gap_len: float = lerp(gap_min_len, gap_max_len, _pseudo_rand(seed_val + 1.0))
		var cycle_len: float = seg_len + gap_len
		
		var move_offset: float = fmod(time * speed * 40.0, cycle_len)
		var seg_start_d: float = current_d + move_offset
		
		if seg_start_d < active_len:
			var seg_end_d: float = minf(seg_start_d + seg_len, active_len)
			
			if seg_end_d > seg_start_d:
				var mid_ratio: float = (seg_start_d + seg_end_d) * 0.5 * inv_pi
				
				var jitter_offset := Vector2.ZERO
				if do_glitch:
					var noise: float = sin(time * 20.0 + segment_index) * cos(time * 50.0 - segment_index)
					jitter_offset = ortho * (noise * glitch_intensity * sin(mid_ratio * PI))
				
				var pos_a: Vector2 = anchor_start + direction * seg_start_d + jitter_offset
				var pos_b: Vector2 = anchor_start + direction * seg_end_d   + jitter_offset
			
				var seg_color: Color = main_color
				var flicker: float = 0.8 + 0.2 * sin(time * 15.0 + segment_index * 2.0)
				var edge_fade: float = sin(mid_ratio * PI)
				seg_color.a *= flicker * edge_fade
				
				if seg_color.a > 0.01:
					if do_bloom:
						var glow_color := seg_color
						glow_color.a *= 0.3
						canvas.draw_line(pos_a, pos_b, glow_color, line_width * bloom_scale, true)
					
					canvas.draw_line(pos_a, pos_b, seg_color, line_width, true)
					canvas.draw_circle(pos_a, line_width, seg_color)
		
		current_d += cycle_len


func _pseudo_rand(x: float) -> float:
	return abs(fmod(sin(x) * 43758.5453123, 1.0))
