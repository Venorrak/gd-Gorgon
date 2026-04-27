@tool
class_name GraphLightningLine extends GraphLine


#region Settings
@export var margin: float = 12.0: ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()

@export_group("Electricity")
@export var bolt_resolution: float = 10.0: ## Length of one segment of the zipper (shorter = more detailed)
	set(v): bolt_resolution = v; emit_changed()
@export var jitter_amount: float = 8.0:    ## Lateral displacement force
	set(v): jitter_amount = v; emit_changed()
@export var animation_speed: float = 15.0: ## Speed of discharge shape change
	set(v): animation_speed = v; emit_changed()

@export_group("Style")
@export var bolt_color: Color = Color(1.0, 0.9, 0.4, 1.0):
	set(v): bolt_color = v; emit_changed()
@export var bolt_width: float = 2.0: ## Thickness of the main colored bolt.
	set(v): bolt_width = v; emit_changed()

@export var core_width: float = 1.0:     ## Thickness of the bright white inner core.
	set(v): core_width = v; emit_changed()
@export var glow_intensity: float = 0.5: ## Multiplier for the outer glow transparency.
	set(v): glow_intensity = v; emit_changed()
#endregion


## [Points Cache] Reused each frame — no per-frame allocations.
var _points: PackedVector2Array


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true): return
	
	var alpha: float = context.get("alpha", 1.0)
	var final_color: Color = context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else bolt_color
	final_color.a *= alpha
	if final_color.a <= 0.01: return
	
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2 = delta_vector / total_length
	var ortho: Vector2 = direction.orthogonal()
	var anchor_start: Vector2 = start + direction * margin
	var anchor_end: Vector2 = end - direction * margin
	var active_len: float = (anchor_end - anchor_start).length()
	
	var segments: int = max(2, int(active_len / max(bolt_resolution, 1.0)))
	var needed_size: int = segments + 1
	
	if _points.size() != needed_size: _points.resize(needed_size)
	
	_points[0] = anchor_start
	_points[segments] = anchor_end
	
	var time_seed: float = floor(Time.get_ticks_msec() * 0.001 * animation_speed)
	
	for i in range(1, segments):
		var t: float = float(i) / segments
		var base_pos: Vector2 = anchor_start.lerp(anchor_end, t)
		var noise_seed: float = float(i) * 132.5 + time_seed * 53.1
		var rand_val: float = (fmod(sin(noise_seed) * 43758.5453, 1.0) - 0.5) * 2.0
		var envelope: float = sin(t * PI)
		_points[i] = base_pos + ortho * (rand_val * jitter_amount * envelope)
	
	var glow_color: Color = final_color
	glow_color.a *= glow_intensity
	canvas.draw_polyline(_points, glow_color, bolt_width * 3.0, true)
	canvas.draw_polyline(_points, final_color, bolt_width, true)
	
	if core_width > 0.001:
		var core_color := Color(1.0, 1.0, 1.0, final_color.a)
		canvas.draw_polyline(_points, core_color, core_width, true)
