// Soft cartoon shading for the crew members: flat colour, wrapped (soft) diffuse light so the shade side never goes
// black, a gentle rim light and a soft highlight. Used by CharacterModel for every body part.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = albedo.rgb * rim * rim_strength;
}
