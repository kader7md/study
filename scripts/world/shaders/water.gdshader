// Lakes, rivers and the sea: one big plane at the water level. The depth comes from the terrain heightmap, so
// shallow water by the shore is lighter, with a soft line of foam; gentle waves move the normals.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float cell = 5.0;
uniform vec3 shallow : source_color = vec3(0.22, 0.50, 0.52);
uniform vec3 deep : source_color = vec3(0.04, 0.17, 0.27);

varying vec3 wpos;

float hm(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(grid_size) - ivec2(1));
	return texelFetch(hmap, c, 0).r;
}

float ground(vec2 xz) {
	vec2 g = (xz - grid_origin) / cell;
	ivec2 c = ivec2(floor(g));
	vec2 f = fract(g);
	float a = mix(hm(c), hm(c + ivec2(1, 0)), f.x);
	float b = mix(hm(c + ivec2(0, 1)), hm(c + ivec2(1, 1)), f.x);
	return mix(a, b, f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = max(wpos.y - ground(wpos.xz), 0.0);
	vec2 p = wpos.xz;
	float t = TIME;
	// a few crossing wave trains: slope of the summed sines
	float dx = 0.0;
	float dz = 0.0;
	dx += cos(p.x * 0.09 + p.y * 0.03 + t * 1.2) * 0.09;
	dz += cos(p.y * 0.11 - p.x * 0.02 - t * 0.9) * 0.08;
	dx += cos(p.x * 0.31 - p.y * 0.22 + t * 2.1) * 0.035;
	dz += cos(p.y * 0.37 + p.x * 0.19 + t * 1.7) * 0.035;
	dx += cos(p.x * 1.3 + p.y * 0.7 + t * 3.3) * 0.012;
	dz += cos(p.y * 1.1 - p.x * 0.9 - t * 2.9) * 0.012;
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 7.0, depth));
	float foam = (1.0 - smoothstep(0.05, 0.7, depth)) * (0.6 + 0.4 * sin(t * 1.5 + p.x * 0.4 + p.y * 0.3));
	col = mix(col, vec3(0.85, 0.9, 0.9), foam * 0.55);
	ALBEDO = col;
	ALPHA = mix(0.45, 0.93, smoothstep(0.0, 3.5, depth));
	ROUGHNESS = 0.07;
	SPECULAR = 0.55;
}
