@tool
class_name GraphMatrixLine extends GraphLine


#region Settings
@export var margin: float = 12.0: ## Offset from the start/end point to the atom so that the line does not cross the nodes.
	set(v): margin = v; emit_changed()

@export var primary_color: Color = Color(1.0, 1.0, 0.4, 1.0):
	set(v): primary_color = v; emit_changed()
@export var secondary_color: Color = Color(0.4, 1.0, 1.0, 1.0):
	set(v): secondary_color = v; emit_changed()

@export_group("Motion & Behavior")
@export var speed: float = 2.0: ## Movement speed 0 = flickering mode in place.
	set(v): speed = v; emit_changed()
@export var density: float = 15.0: ## Density of elements
	set(v): density = v; emit_changed()
@export var spread_width: float = 30.0: ## Cloud width (static spread)
	set(v): spread_width = v; emit_changed()

@export_group("Floating Animation")
@export var hover_amplitude: float = 5.0: ## Vertical (orthogonal) oscillation distance.
	set(v): hover_amplitude = v; emit_changed()
@export var hover_speed: float = 2.0: ## Frequency of the floating oscillation.
	set(v): hover_speed = v; emit_changed()

@export_group("Glitch Effect")
@export var jitter_intensity: float = 2.0: ## Intensity of high-frequency position noise.
	set(v): jitter_intensity = v; emit_changed()
@export var jitter_frequency: float = 50.0: ## Speed of the jitter noise.
	set(v): jitter_frequency = v; emit_changed()
@export var flicker_intensity: float = 0.5: ## Brightness flicker strength
	set(v): flicker_intensity = v; emit_changed()
@export var static_pulse_speed: float = 2.0: ## Disappearance speed, if speed == 0
	set(v): static_pulse_speed = v; emit_changed()

@export_group("Element Types (Mixable)")
@export var use_text: bool = true:
	set(v): use_text = v; _modes_dirty = true; notify_property_list_changed(); emit_changed()
@export var use_squares: bool = false:
	set(v): use_squares = v; _modes_dirty = true; emit_changed()
@export var use_circles: bool = false:
	set(v): use_circles = v; _modes_dirty = true; emit_changed()
@export var use_textures: bool = false:
	set(v): use_textures = v; _modes_dirty = true; notify_property_list_changed(); emit_changed()

@export_group("Element Options")
@export var size_min: float = 6.0:
	set(v): size_min = v; emit_changed()
@export var size_max: float = 18.0:
	set(v): size_max = v; emit_changed()

@export var charset: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<>?#@&":
	set(v): charset = v; emit_changed()
@export var font: Font:
	set(v): font = v; emit_changed()
@export var custom_texture: Texture2D:
	set(v): custom_texture = v; emit_changed()
#endregion


## [Modes Cache] Rebuilt only when use_* flags change.
var _active_modes: Array[int] = []
var _modes_dirty: bool = true


func _get_property_list() -> Array:
	var props = []
	var font_usage = PROPERTY_USAGE_DEFAULT if use_text    else PROPERTY_USAGE_NO_EDITOR
	var tex_usage  = PROPERTY_USAGE_DEFAULT if use_textures else PROPERTY_USAGE_NO_EDITOR
	props.append({ "name": "charset",        "type": TYPE_STRING, "usage": font_usage })
	props.append({ "name": "font",           "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Font",      "usage": font_usage })
	props.append({ "name": "custom_texture", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Texture2D", "usage": tex_usage  })
	return props


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true): return
	
	if _modes_dirty:
		_active_modes.clear()
		if use_text:    _active_modes.append(0)
		if use_squares: _active_modes.append(1)
		if use_circles: _active_modes.append(2)
		if use_textures and custom_texture != null: _active_modes.append(3)
		_modes_dirty = false
	if _active_modes.is_empty(): return
	
	var alpha: float = context.get("alpha", 1.0)
	var delta_vector: Vector2 = end - start
	var total_length: float = delta_vector.length()
	if total_length <= margin * 2.0: return
	
	var direction: Vector2 = delta_vector / total_length
	var ortho: Vector2 = direction.orthogonal()
	var anchor_start: Vector2 = start + direction * margin
	var anchor_end: Vector2 = end - direction * margin
	var active_len: float = (anchor_end - anchor_start).length()
	
	var time: float = Time.get_ticks_msec() * 0.001
	var used_font: Font = font if font else ThemeDB.fallback_font
	var element_count: int = int(active_len / density)
	var modes_size: int = _active_modes.size()
	var charset_len: int = charset.length()
	var is_moving: bool = abs(speed) > 0.01
	var do_jitter: bool = jitter_intensity > 0.01
	var do_flicker: bool = flicker_intensity > 0.01
	var inv_edge: float = 1.0 / 20.0

	for i in range(element_count):
		var seed_val: float = i * 45.123
		
		var rand_spread:    float = _pseudo_rand(seed_val)        * 2.0 - 1.0
		var rand_scale:     float = _pseudo_rand(seed_val + 10.0)
		var rand_color_mix: float = _pseudo_rand(seed_val + 20.0)
		var rand_type_val:  float = _pseudo_rand(seed_val + 30.0)
		var rand_char_val:  float = _pseudo_rand(seed_val + 40.0)
		
		var current_dist: float
		var alpha_mult: float = 1.0
		
		if is_moving:
			var parallax: float = 0.8 + rand_scale * 0.4
			current_dist = fmod(time * speed * 20.0 * parallax + i * density, active_len + 40.0) - 20.0
		else:
			current_dist = i * density
			if static_pulse_speed > 0.01:
				alpha_mult = sin(time * static_pulse_speed + seed_val * 10.0) * 0.5 + 0.5
		
		if current_dist < -20.0 or current_dist > active_len + 20.0: continue
		
		var spread_offset: Vector2 = ortho * (rand_spread * spread_width)
		var hover_val: float = sin(time * hover_speed + seed_val * 5.0) * hover_amplitude
		var jitter_vec := Vector2.ZERO
		if do_jitter:
			jitter_vec.x = sin(time * jitter_frequency + seed_val)
			jitter_vec.y = cos(time * jitter_frequency + seed_val * 2.0)
			jitter_vec *= jitter_intensity
		
		var final_pos: Vector2 = anchor_start + direction * current_dist + spread_offset + ortho * hover_val + jitter_vec
		
		var element_color: Color = primary_color.lerp(secondary_color, snapped(rand_color_mix, 0.5))
		
		var edge_fade: float = 1.0
		if current_dist < 20.0: edge_fade = current_dist * inv_edge
		elif current_dist > active_len - 20.0: edge_fade = (active_len - current_dist) * inv_edge
		
		if do_flicker and sin(time * 30.0 + seed_val) > (1.0 - flicker_intensity): alpha_mult *= 0.3
		
		element_color.a = alpha * clamp(edge_fade, 0.0, 1.0) * alpha_mult * (0.4 + 0.6 * rand_scale)
		if element_color.a <= 0.01: continue
		
		var size: float = lerp(size_min, size_max, rand_scale)
		var mode: int = _active_modes[int(rand_type_val * 100) % modes_size]
		
		match mode:
			0: canvas.draw_string(used_font, final_pos, charset[int(rand_char_val * 100) % charset_len], HORIZONTAL_ALIGNMENT_CENTER, -1, int(size), element_color)
			1: canvas.draw_rect(Rect2(final_pos - Vector2.ONE * (size * 0.5), Vector2.ONE * size), element_color, true)
			2: canvas.draw_circle(final_pos, size * 0.5, element_color)
			3: canvas.draw_texture_rect(custom_texture, Rect2(final_pos - Vector2.ONE * (size * 0.5), Vector2.ONE * size), false, element_color)


func _pseudo_rand(x: float) -> float:
	return abs(fmod(sin(x) * 12345.6789, 1.0))
