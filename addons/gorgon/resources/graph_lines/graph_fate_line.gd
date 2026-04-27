@tool
class_name GraphFateThread extends GraphLine


enum ConnectionMode { OFF, MERGED, SEPARATE }


#region Settings
@export var connection_mode: ConnectionMode = ConnectionMode.MERGED:
	set(v): connection_mode = v; emit_changed()

@export var margin: float = 12.0:          ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()
@export var separate_stride: float = 12.0: ## Distance between parallel lines when [code]ConnectionMode.SEPARATE[/code] is used.
	set(v): separate_stride = v; emit_changed()

@export_group("Visuals")
@export var thread_color: Color = Color(1.0, 0.85, 0.4, 1.0):
	set(v): thread_color = v; emit_changed()
@export var thread_width: float = 2.0:
	set(v): thread_width = v; emit_changed()
@export var glow_strength: float = 0.5:
	set(v): glow_strength = v; emit_changed()
@export var fade_length: float = 40.0: ## Distance over which the thread fades out at the ends.
	set(v): fade_length = v; emit_changed()

@export_group("Weaving")
@export var amplitude: float = 3.0:
	set(v): amplitude = v; emit_changed()
@export var frequency: float = 15.0:
	set(v): frequency = v; emit_changed()
@export var speed: float = 2.0:
	set(v): speed = v; emit_changed()
#endregion


## [Points/Colors Cache] Reused every frame — no per-frame allocations.
var _pts:       PackedVector2Array
var _cols_main: PackedColorArray
var _cols_glow: PackedColorArray


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true) or connection_mode == ConnectionMode.OFF: return
	
	var is_mutual: bool = context.get("conn_mutual", false)
	var is_primary: bool = context.get("is_primary", true)
	if connection_mode == ConnectionMode.MERGED and is_mutual and not is_primary: return
	
	var alpha: float = context.get("alpha", 1.0)
	var final_color: Color = context.get("highlight_color", Color.WHITE) if context.get("highlighted", false) else thread_color
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
	
	if connection_mode == ConnectionMode.SEPARATE and is_mutual:
		anchor_start += ortho * separate_stride
		anchor_end   += ortho * separate_stride
	
	var time: float = Time.get_ticks_msec() * 0.001 * speed if not Engine.is_editor_hint() else 0.0
	var segments: int = max(10, int(active_len / 4.0))
	var needed: int = segments + 1
	
	if _pts.size() != needed:
		_pts.resize(needed)
		_cols_main.resize(needed)
		_cols_glow.resize(needed)
	
	var glow_base_a: float = final_color.a * 0.3 * glow_strength
	var inv_fade: float = 1.0 / max(fade_length, 0.001)
	
	for i in range(needed):
		var t: float = float(i) / segments
		var dist: float = t * active_len
		
		var fade: float
		if dist < fade_length: fade = dist * inv_fade
		elif dist > active_len - fade_length: fade = (active_len - dist) * inv_fade
		else: fade = 1.0
		var smooth_fade: float = fade * fade * (3.0 - 2.0 * fade)
		
		_pts[i] = anchor_start.lerp(anchor_end, t) + ortho * (sin(time + t * frequency) * amplitude)
		
		var c := final_color
		c.a *= smooth_fade
		_cols_main[i] = c
		
		c.a = final_color.a * glow_base_a * smooth_fade
		_cols_glow[i] = c
	
	if glow_strength > 0.01: canvas.draw_polyline_colors(_pts, _cols_glow, thread_width * 4.0, true)
	canvas.draw_polyline_colors(_pts, _cols_main, thread_width, true)
