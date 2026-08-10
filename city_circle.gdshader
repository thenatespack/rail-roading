shader_type canvas_item;

// --- Uniforms for the Heart ---
uniform float heart_radius : hint_range(0.0, 0.5) = 0.1;
uniform vec4 heart_color : source_color = vec4(1.0, 0.2, 0.2, 1.0); // Red

// --- Uniforms for the Influence ---
uniform float influence_radius : hint_range(0.0, 0.9) = 0.4;
uniform vec4 influence_color : source_color = vec4(0.2, 0.5, 1.0, 0.5); // Translucent Blue

// --- Antialiasing width ---
uniform float aa_width : hint_range(0.001, 0.1) = 0.01;

void fragment() {
	// Center UV coordinates
	vec2 uv = UV - 0.5;
	// Calculate distance from center (0.0 to 1.0 range inside rect)
	float dist = length(uv) * 2.0;
	
	// 1. Draw the Influence Ring (largest, softest edges)
	float inf_border = smoothstep(influence_radius, influence_radius - aa_width, dist);
	// Create the hole in the middle so it's only a ring
	float influence = inf_border - smoothstep(heart_radius + aa_width, heart_radius, dist);
	
	// 2. Draw the Heart (smallest, solid)
	float heart = smoothstep(heart_radius, heart_radius - aa_width, dist);
	
	// --- Composition ---
	// Start with influence
	vec4 final_color = influence_color * clamp(influence, 0.0, 1.0);
	// Add the heart on top
	final_color += heart_color * clamp(heart, 0.0, 1.0);
	
	COLOR = final_color;
}