// Ground of the overworld (Terrain). Two uses of the same shader so both look identical:
//  - is_grid: flat chunk meshes displaced by the heightmap (hmap, one texel per grid vertex). Hidden near the
//    rails, where the fine ribbon mesh takes over.
//  - ribbon: the fine strip along the rails, real vertex positions; COLOR.r marks the track ballast.
// Colour from height, slope and the biome map (r: distance to the track, g: dryness, b: snow line, a: quest site).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform sampler2D biome : filter_linear, repeat_disable;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform sampler2D patches : filter_linear_mipmap, repeat_enable;
uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform float cell = 5.0;
uniform float water_level = -4.0;
uniform bool is_grid = true;
uniform float skirt = 6.0;
uniform float ribbon_cut = 30.0;

const vec3 GRASS = vec3(0.27, 0.40, 0.17);
const vec3 GRASS_DARK = vec3(0.15, 0.27, 0.11);
const vec3 GRASS_DRY = vec3(0.50, 0.47, 0.26);
const vec3 MOWN = vec3(0.36, 0.47, 0.22);
const vec3 DIRT = vec3(0.38, 0.29, 0.19);
const vec3 SAND = vec3(0.70, 0.62, 0.44);
const vec3 WET_SAND = vec3(0.42, 0.37, 0.27);
const vec3 ROCK = vec3(0.42, 0.40, 0.38);
const vec3 ROCK_DARK = vec3(0.25, 0.24, 0.23);
const vec3 ROCK_WARM = vec3(0.47, 0.40, 0.33);
const vec3 SNOW = vec3(0.88, 0.90, 0.94);
const vec3 BALLAST = vec3(0.36, 0.34, 0.32);

varying vec3 wpos;
varying vec3 wnorm;

float hm(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(grid_size) - ivec2(1));
	return texelFetch(hmap, c, 0).r;
}

void vertex() {
	if (is_grid) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		ivec2 c = ivec2(round((w.xz - grid_origin) / cell));
		float h = hm(c);
		float hl = hm(c - ivec2(1, 0));
		float hr = hm(c + ivec2(1, 0));
		float hd = hm(c - ivec2(0, 1));
		float hu = hm(c + ivec2(0, 1));
		VERTEX.y = h - UV2.x * skirt;
		NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hd - hu));
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 buv = ((wpos.xz - grid_origin) / cell + 0.5) / grid_size;
	vec4 b = texture(biome, buv);
	float au = b.r * 64.0;
	if (is_grid && au < ribbon_cut) {
		discard;
	}
	vec3 n = normalize(wnorm);
	float slope = 1.0 - n.y;
	float h = wpos.y;
	float dry = b.g;
	float snow_line = b.b * 512.0;
	float site = smoothstep(0.8, 0.98, b.a);
	float trail = smoothstep(0.3, 0.48, b.a) * (1.0 - smoothstep(0.55, 0.75, b.a));

	float big = texture(patches, wpos.xz * 0.0021).r;
	float mid = texture(patches, wpos.xz * 0.013).r;
	float fine = texture(grain, wpos.xz * 0.19).r;
	float patch = smoothstep(0.42, 0.72, big);
	float patch2 = smoothstep(0.4, 0.75, mid);

	// meadow: dark and light patches, dry grass where the theme is dry
	vec3 col = mix(GRASS, GRASS_DARK, patch * 0.85);
	col = mix(col, GRASS_DRY, clamp(dry * 1.2 * (0.4 + patch2), 0.0, 0.85));
	// mown, lighter grass on the quest sites
	col = mix(col, MOWN, site * 0.8);
	// trodden trails
	col = mix(col, mix(DIRT, GRASS_DRY, 0.35) * (0.85 + 0.3 * mid), trail * 0.85);
	// bare earth on medium slopes
	col = mix(col, DIRT, smoothstep(0.16, 0.30, slope + (mid - 0.5) * 0.2) * 0.85);
	// alpine: sparse grass and scree below the snow line
	float alpine = smoothstep(snow_line - 70.0, snow_line - 5.0, h + (big - 0.5) * 60.0);
	col = mix(col, mix(ROCK, GRASS_DRY, 0.35), alpine * 0.75);
	// rock on steep ground, banded like strata
	float strata = sin(h * 0.45 + big * 14.0 + mid * 4.0) * 0.5 + 0.5;
	vec3 rock = mix(ROCK_DARK, mix(ROCK, ROCK_WARM, dry), 0.45 + 0.25 * strata + 0.3 * mid);
	float rock_k = smoothstep(0.26, 0.38, slope + (mid - 0.5) * 0.25);
	col = mix(col, rock, rock_k);
	// snow above the snow line, sliding off the steepest faces
	float snow_k = smoothstep(snow_line - 4.0, snow_line + 8.0, h + (big - 0.5) * 40.0) * (1.0 - smoothstep(0.28, 0.46, slope + (mid - 0.5) * 0.15));
	col = mix(col, SNOW, snow_k);
	// sandy shores, wet sand under water
	col = mix(col, SAND, 1.0 - smoothstep(water_level + 0.9, water_level + 2.6, h));
	col = mix(col, WET_SAND, 1.0 - smoothstep(water_level - 1.5, water_level + 0.2, h));
	if (!is_grid) {
		col = mix(col, BALLAST * (0.8 + fine * 0.3), COLOR.r);
	}
	ALBEDO = col * mix(0.78, 1.0, fine);
	ROUGHNESS = mix(0.96, 0.55, snow_k * 0.6);
	SPECULAR = 0.25;
}
