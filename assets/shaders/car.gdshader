shader_type canvas_item;

// Tints the car body to a vivid color while keeping body shading. Bodies are
// drawn as grayscale pixels (luminance = shading); glass, wheels, lights and
// outline are drawn with chroma and pass through unchanged. Saturation is
// boosted so each car reads as a distinct, vibrant color.
uniform vec4 tint : source_color = vec4(0.93, 0.10, 0.16, 1.0);

void fragment() {
	vec4 tex_pixel = texture(TEXTURE, UV);
	vec3 rgb = tex_pixel.rgb;
	float cmin = min(rgb.r, min(rgb.g, rgb.b));
	float cmax = max(rgb.r, max(rgb.g, rgb.b));
	float chroma = cmax - cmin;
	float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	if (tex_pixel.a >= 0.05 && chroma < 0.045 && lum >= 0.32) {
		float shade = clamp(lum / 0.78, 0.62, 1.18);
		vec3 col = tint.rgb * shade;
		float gray = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(gray), col, 1.25);   // saturation boost
		COLOR = vec4(clamp(col, 0.0, 1.0), tex_pixel.a);
	} else {
		COLOR = tex_pixel;
	}
}