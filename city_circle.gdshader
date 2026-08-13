shader_type canvas_item;

// --- Uniforms for the Heart ---
uniform float heart_radius : hint_range(0.0, 0.35) = 0.03;
uniform vec4 heart_color : source_color = vec4(1.0, 0.2, 0.2, 1.0); // Red

// --- Uniforms for the Influence ---
uniform float influence_radius : hint_range(0.0, 0.98) = 0.5;
uniform vec4 influence_color : source_color = vec4(0.2, 0.5, 1.0, 0.5); // Translucent Blue

// --- Zone uniforms (housing / commercial / industrial) ---
// This shader uses the exact same integer hash as MapGenerator.hash3i(), so the
// zones shown here match the zones the CPU uses when placing buildings.
uniform bool show_zones = true;
uniform int zone_seed_i = 0;
uniform int cell_size : hint_range(1, 16) = 4;      // district cell size, in tiles
uniform int zone_split_a : hint_range(0, 1024) = 512; // housing fraction (of 1024)
uniform int zone_split_b : hint_range(0, 1024) = 819; // housing + commercial fraction (of 1024)
uniform float zone_rect_tiles = 16.0;                 // marker rect size, in tiles
uniform float zone_opacity : hint_range(0.0, 1.0) = 0.75;
uniform vec4 residential_color : source_color = vec4(0.25, 0.75, 0.3, 1.0); // Housing (green)
uniform vec4 commercial_color : source_color = vec4(0.3, 0.55, 1.0, 1.0);   // Commercial (blue)
uniform vec4 industrial_color : source_color = vec4(0.95, 0.75, 0.2, 1.0);  // Industry (yellow)

// --- Antialiasing width ---
uniform float aa_width : hint_range(0.001, 0.1) = 0.01;

// 32-bit wrap hash. Must match MapGenerator.hash3i() exactly.
uint hash3i(int ix, int iy, int iz) {
	uint h = uint(ix) * 374761393u + uint(iy) * 668265263u + uint(iz) * 180461551u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return h;
}

// Returns 0 = housing, 1 = commercial, 2 = industrial for a tile offset (dx, dy)
// measured in tiles from the city's tile. Matches MapGenerator.get_zone().
int get_zone(int dx, int dy) {
	int cs = max(cell_size, 1);
	int cx = int(floor(float(dx) / float(cs)));
	int cy = int(floor(float(dy) / float(cs)));
	int best_cx = cx;
	int best_cy = cy;
	int best_d2 = 2147483647;
	for (int ox = -1; ox <= 1; ox++) {
		for (int oy = -1; oy <= 1; oy++) {
			int cxx = cx + ox;
			int cyy = cy + oy;
			uint h = hash3i(cxx, cyy, zone_seed_i);
			int jx = int(h % uint(cs));
			int jy = int((h >> 16u) % uint(cs));
			int center_x = cxx * cs + jx;
			int center_y = cyy * cs + jy;
			int dxx = center_x - dx;
			int dyy = center_y - dy;
			int d2 = dxx * dxx + dyy * dyy;
			if (d2 < best_d2) {
				best_d2 = d2;
				best_cx = cxx;
				best_cy = cyy;
			}
		}
	}
	uint bh = hash3i(best_cx, best_cy, zone_seed_i + 1000003);
	int bucket = int(bh >> 22u);
	if (bucket < zone_split_a) return 0;
	if (bucket < zone_split_b) return 1;
	return 2;
}

void fragment() {
	// Center UV coordinates
	vec2 uv = UV - 0.5;
	// Calculate distance from center (0.0 to 1.0 range inside rect)
	float dist = length(uv) * 2.0;

	// Influence ring mask (annulus between heart edge and influence edge)
	float influence = smoothstep(influence_radius, influence_radius - aa_width, dist)
		- smoothstep(heart_radius + aa_width, heart_radius, dist);
	// Solid heart in the middle
	float heart = smoothstep(heart_radius, heart_radius - aa_width, dist);

	vec4 final_color = vec4(0.0);

	if (show_zones) {
		// Exact integer tile offset under this pixel, relative to the city's tile.
		// The rect is centered on the city and spans zone_rect_tiles tiles.
		int dx = int(floor(UV.x * zone_rect_tiles - (zone_rect_tiles - 1.0) * 0.5));
		int dy = int(floor(UV.y * zone_rect_tiles - (zone_rect_tiles - 1.0) * 0.5));

		vec4 zone_color;
		int zone = get_zone(dx, dy);
		if (zone == 0) {
			zone_color = residential_color;
		} else if (zone == 1) {
			zone_color = commercial_color;
		} else {
			zone_color = industrial_color;
		}

		// Zones fill the influence ring, tinted by zone_opacity
		final_color = vec4(zone_color.rgb, 1.0) * influence * zone_opacity;
	} else {
		final_color = influence_color * influence;
	}

	// Draw the heart on top
	final_color += heart_color * heart;

	COLOR = final_color;
}
