// The Mountain's ground: biome colour per vertex (COLOR.rgb, COLOR.a = snow), tiling textures baked in Blender
// (blender/scripts/build_mountain.py): ground grain on flat ground, triplanar rock on steep faces, snow on top.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float rock_scale = 0.11;
uniform float ground_scale = 0.22;
uniform vec3 rock_tint : source_color = vec3(0.85, 0.8, 0.74);

varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 w, float s) {
	return texture(tex, p.zy * s).rgb * w.x + texture(tex, p.xz * s).rgb * w.y + texture(tex, p.xy * s).rgb * w.z;
}

void fragment() {
	vec3 n = normalize(lnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float steep = smoothstep(0.38, 0.62, 1.0 - n.y);
	vec3 rock = triplanar(rock_tex, lpos, w, rock_scale) * rock_tint;
	// faint horizontal strata on the cliffs
	rock *= 0.88 + 0.12 * sin(lpos.y * 1.7 + sin(lpos.x * 0.05) * 3.0);
	vec3 ground = texture(ground_tex, lpos.xz * ground_scale).rgb * COLOR.rgb * 1.35;
	vec3 snow = texture(snow_tex, lpos.xz * 0.15).rgb;
	float snow_amt = COLOR.a;
	vec3 flat_col = mix(ground, snow, snow_amt);
	// snow also dusts the rock up high
	vec3 rock_col = mix(rock, mix(rock, snow, 0.55), snow_amt * smoothstep(0.85, 0.55, 1.0 - n.y));
	ALBEDO = mix(flat_col, rock_col, steep);
	ROUGHNESS = mix(0.95, 0.75, snow_amt);
	SPECULAR = 0.25;
}
