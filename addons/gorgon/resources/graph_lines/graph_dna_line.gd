@tool
class_name GraphDnaLine extends GraphLine


#region Settings
@export var margin: float = 12.0: ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()

@export var strand_a_color: Color = Color(0.2, 0.7, 1.0, 1.0):
	set(v): strand_a_color = v; emit_changed()
@export var strand_b_color: Color = Color(1.0, 0.2, 0.5, 1.0):
	set(v): strand_b_color = v; emit_changed()
@export var link_color: Color = Color(1.0, 1.0, 1.0, 0.5):
	set(v): link_color = v; emit_changed()

@export_group("Helix Shape")
@export var amplitude: float = 6.0:    ## Spiral width.
	set(v): amplitude = v; emit_changed()
@export var period: float = 40.0:      ## Distance in pixels for one full 360-degree turn.
	set(v): period = v; emit_changed()
@export var rotation_speed: float = 4.0:
	set(v): rotation_speed = v; emit_changed()
@export var strand_width: float = 2.0: ## Thickness of the two main strands.
	set(v): strand_width = v; emit_changed()

@export_group("Links (DNA)")
@export var show_links: bool = true: ## Whether to draw connecting bridges between strands.
	set(v): show_links = v; emit_changed()
@export var link_density: int = 5:   ## Skip N points before drawing a bridge.
	set(v): link_density = v; emit_changed()
@export var link_width: float = 1.0: ## Thickness of the connecting bridges.
	set(v): link_width = v; emit_changed()
#endregion


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true): return
	
	var is_mutual: bool = context.get("conn_mutual", false)
	var is_primary: bool = context.get("is_primary", true)
	if is_mutual and not is_primary: return
	
	var alpha: float = context.get("alpha", 1.0)
	var highlight: bool = context.get("highlighted", false)
	var high_color: Color = context.get("highlight_color", Color.WHITE)
	
	var color_a:    Color = high_color if highlight else strand_a_color
	var color_b:    Color = high_color if highlight else strand_b_color
	var color_link: Color = high_color if highlight else link_color
	
	## Геометрия
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2    = delta_vector / total_length
	var ortho: Vector2        = direction.orthogonal()
	var anchor_start: Vector2 = start + direction * margin
	var active_len: float     = total_length - margin * 2.0
	
	var time: float = 0.0
	if not Engine.is_editor_hint():
		time = Time.get_ticks_msec() * 0.001 * rotation_speed
	
	var freq: float = TAU / maxf(period, 1.0)
	
	var step_size: float = 3.0
	var steps: int = int(active_len / step_size)
	
	var prev_pos_a: Vector2 = Vector2.ZERO
	var prev_pos_b: Vector2 = Vector2.ZERO
	
	for i in range(steps + 1):
		var d: float   = minf(i * step_size, active_len)
		var angle: float = d * freq - time
		
		var sin_val: float = sin(angle)
		var cos_val: float = cos(angle)
		
		var center_pos: Vector2 = anchor_start + direction * d
		var offset_vec: Vector2 = ortho * (sin_val * amplitude)
		
		var pos_a: Vector2 = center_pos + offset_vec
		var pos_b: Vector2 = center_pos - offset_vec
		
		var z_a: float = remap(cos_val,  -1.0, 1.0, 0.3, 1.0)
		var z_b: float = remap(-cos_val, -1.0, 1.0, 0.3, 1.0)
		
		if i > 0:
			var col_a: Color = color_a; col_a.a *= alpha * z_a
			canvas.draw_line(prev_pos_a, pos_a, col_a, strand_width, true)
			
			var col_b: Color = color_b; col_b.a *= alpha * z_b
			canvas.draw_line(prev_pos_b, pos_b, col_b, strand_width, true)
			
			if show_links and (i % link_density == 0):
				var col_l: Color = color_link
				col_l.a *= alpha * minf(z_a, z_b) * 0.8
				canvas.draw_line(pos_a, pos_b, col_l, link_width, true)
		
		prev_pos_a = pos_a
		prev_pos_b = pos_b
