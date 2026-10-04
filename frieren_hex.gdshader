
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// ---------- Hex grid ----------
uniform float hex_scale = 8.0;                 // number of hexagons across the UV
uniform vec2  uv_stretch = vec2(1.0, 1.0);     // fix stretched hexes on non-square meshes
uniform float edge_width = 0.04;               // thickness of the bright line
uniform float edge_softness = 0.02;            // anti-aliasing of the line
uniform float glow_width = 0.18;               // how far the glow bleeds inward from the line

// ---------- Colors ----------
uniform vec4 edge_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.1, 0.55, 1.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.05, 0.25, 0.5, 1.0);
uniform float edge_intensity = 3.0;            // >1 = HDR, needs Environment glow to bloom
uniform float glow_intensity = 1.2;
uniform float fill_alpha = 0.12;

// ---------- Fresnel (brighter at grazing angles) ----------
uniform float fresnel_power = 2.5;
uniform float fresnel_strength = 1.0;

// ---------- Per-cell flicker ----------
uniform float flicker_speed = 2.0;
uniform float flicker_amount = 0.5;
uniform float sparkle_threshold = 0.96;        // closer to 1.0 = rarer bright cells

// ---------- Spawn animation ----------
uniform float reveal : hint_range(0.0, 1.5) = 1.5; // animate 0 -> 1.5 to "cast" the shield
uniform vec2  reveal_center = vec2(0.5, 0.5);

// ---------- Impact ripple ----------
uniform vec3  hit_pos = vec3(0.0);             // object-space position of last hit
uniform float hit_time = 100.0;                // seconds since hit (set from script)
uniform float ripple_speed = 6.0;
uniform float ripple_freq = 8.0;
uniform float ripple_strength = 1.5;

varying vec3 local_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// returns (local offset from cell center xy, cell id zw)
vec4 hex_coords(vec2 uv) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hC = floor(vec4(uv, uv - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(uv - hC.xy * s, uv - (hC.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw)
		? vec4(h.xy, hC.xy)
		: vec4(h.zw, hC.zw + 0.5);
}

// 0 at cell center, 0.5 at the hexagon's edge
float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.7320508)));
	return max(c, p.x);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// --- 1. Hex grid ---
	// swap x/y so hexes are pointy-top like in the anime
	vec2 uv = UV.yx * uv_stretch.yx * hex_scale;
	vec4 hc = hex_coords(uv);
	float d = hex_dist(hc.xy);
	float rnd = hash21(hc.zw);

	// --- 2. Edge line + inner glow ---
	float line = smoothstep(0.5 - edge_width - edge_softness, 0.5 - edge_width, d);
	float glow = smoothstep(0.5 - glow_width, 0.5, d);
	glow = glow * glow;

	// --- 3. Per-cell flicker + rare sparkle ---
	float flick = 0.5 + 0.5 * sin(TIME * flicker_speed + rnd * 6.2831);
	float cell_brightness = 1.0 - flicker_amount + flicker_amount * flick;
	float sparkle = step(sparkle_threshold, fract(rnd * 7.0 + TIME * 0.15));

	// --- 4. Fresnel ---
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	fres = fres * fresnel_strength;

	// --- 5. Impact ripple (ring that travels outward and fades) ---
	float dist_hit = distance(local_pos, hit_pos);
	float ring = sin(dist_hit * ripple_freq - hit_time * ripple_speed);
	ring = max(ring, 0.0) * exp(-dist_hit * 1.5) * exp(-hit_time * 2.0) * ripple_strength;

	// --- 6. Spawn reveal (hexes pop in outward from a center, staggered by rnd) ---
	float r = distance(UV, reveal_center) + rnd * 0.15;
	float visible = 1.0 - smoothstep(reveal - 0.1, reveal, r);

	// --- 7. Combine ---
	float boost = cell_brightness + sparkle * 1.5 + ring + fres;

	vec3 col = fill_color.rgb * fill_alpha;
	col += glow_color.rgb * glow * glow_intensity * boost;
	col += edge_color.rgb * line * edge_intensity * boost;

	float a = fill_alpha * (0.5 + cell_brightness * 0.5);
	a += glow * 0.5 * glow_intensity;
	a += line;
	a += (sparkle * 0.3 + ring * 0.3 + fres * 0.2);

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * visible;
}
