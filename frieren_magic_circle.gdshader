
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Put this on a QuadMesh (faces +Z). Everything is procedural, no textures needed.

// ---------- Layout ----------
uniform int   petal_count = 6;            // eye-shaped petals with a circle in each
uniform int   glyph_count = 42;           // glyph cells around the text ring
uniform float petal_radius = 0.45;        // distance of petal circle from center
uniform float lens_length = 0.28;         // half-length of the eye shape
uniform float lens_width = 0.15;          // half-width of the eye shape

// ---------- Look ----------
uniform vec4  core_color : source_color = vec4(0.88, 0.97, 1.0, 1.0);
uniform vec4  glow_color : source_color = vec4(0.25, 0.6, 1.0, 1.0);
uniform vec4  fill_color : source_color = vec4(0.05, 0.2, 0.55, 1.0);
uniform float line_width = 0.006;
uniform float glyph_thinning = 0.002;     // glyph strokes slightly thinner than main lines
uniform float core_intensity = 2.5;       // >1 = HDR, enable Environment glow to bloom
uniform float glow_strength = 0.35;
uniform float glow_falloff = 55.0;        // higher = tighter glow
uniform float fill_alpha = 0.18;

// ---------- Hand-drawn "boil" ----------
uniform float boil_fps = 8.0;             // anime-style stepped redraw rate
uniform float wobble_amount = 0.012;      // how far lines wander
uniform float wobble_freq = 7.0;

// ---------- Motion ----------
uniform float glyph_spin = 0.15;          // rad/sec, text ring
uniform float core_spin = -0.08;          // rad/sec, petals + center
uniform float pulse_speed = 2.0;

// ---------- Gameplay controls ----------
uniform float reveal : hint_range(0.0, 1.3) = 1.3;   // 0 -> 1.3 draws the circle outward
uniform float charge : hint_range(0.0, 1.0) = 0.0;   // 1 = all petals lit, brighter (about to fire)
uniform float flash : hint_range(0.0, 1.0) = 0.0;    // quick white-out on fire

float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// distance to the OUTLINE of an eye/lens shape (two arcs meeting at tips on the x axis)
float d_lens(vec2 q, float L, float W) {
	float Rl = (L * L + W * W) / (2.0 * W);
	float c = Rl - W;
	float s = q.y >= 0.0 ? 1.0 : -1.0;
	float d = abs(length(q - vec2(0.0, -c * s)) - Rl);
	return max(d, abs(q.x) - L);
}

void fragment() {
	// ---- 0. Rune space: -1..1, y up ----
	vec2 p0 = (UV - 0.5) * 2.0;
	p0.y = -p0.y;
	float r0 = length(p0);

	// ---- 1. Hand-drawn boil: noise-warp the coordinates, re-rolled at a low fps ----
	float t = floor(TIME * boil_fps);
	vec2 w = vec2(
		vnoise(p0 * wobble_freq + vec2(t * 1.7, 0.0)),
		vnoise(p0 * wobble_freq + vec2(31.4, t * 2.3))) - 0.5;
	vec2 p = p0 + w * wobble_amount * 2.0;
	float wmod = 0.75 + 0.5 * vnoise(p0 * 38.0 + t); // line thickness varies a little

	float D = 10.0; // running minimum distance to ANY line in the rune

	// ---- 2. Outer rings (double lines) ----
	float r = length(p);
	D = min(D, abs(r - 0.97));
	D = min(D, abs(r - 0.955));
	D = min(D, abs(r - 0.73));
	D = min(D, abs(r - 0.715));

	// ---- 3. Glyph ring: polar cells, each with two procedural "letters" ----
	float R_in = 0.73;
	float R_out = 0.935;
	float band = R_out - R_in;
	float rmid = 0.5 * (R_in + R_out);

	vec2 pg = rot(TIME * glyph_spin) * p;
	float a = atan(pg.y, pg.x);
	float cf = a / TAU * float(glyph_count);
	float gid = mod(floor(cf), float(glyph_count));
	float lu = fract(cf) - 0.5;
	float lv = (length(pg) - rmid) / band;           // -0.5 .. 0.5 across the band
	float cellw = TAU * length(pg) / float(glyph_count) / band;

	float row = step(0.0, lv);
	vec2 gl = vec2(lu * cellw, lv - (row - 0.5) * 0.5);
	float h = hash21(vec2(gid, row));
	float gd;
	if (h < 0.2) {
		gd = abs(length(gl) - 0.16);                          // ring
	} else if (h < 0.4) {
		gd = sd_seg(gl, vec2(0.0, -0.2), vec2(0.0, 0.2));     // bar
	} else if (h < 0.6) {
		gd = max(abs(length(gl - vec2(0.0, 0.04)) - 0.17), gl.y - 0.04); // cup
	} else if (h < 0.8) {
		gd = min(length(gl - vec2(-0.14, 0.0)), length(gl - vec2(0.14, 0.0))); // two dots
	} else {
		gd = min(sd_seg(gl, vec2(-0.16, -0.16), vec2(0.16, 0.16)),
				 sd_seg(gl, vec2(-0.16, 0.16), vec2(0.16, -0.16)));           // cross
	}
	if (hash21(vec2(gid + 91.0, row)) > 0.93) gd = 1.0;       // some empty cells
	float dG = gd * band + glyph_thinning;
	dG = max(dG, abs(length(pg) - rmid) - band * 0.5);        // keep inside the band
	D = min(D, dG);

	// ---- 4. Petals (domain-folded so we don't loop) ----
	vec2 pc = rot(TIME * core_spin) * p;
	float N = float(petal_count);
	float sector = TAU / N;
	float ac = atan(pc.y, pc.x);
	float rc = length(pc);

	// petal axes sit at k * sector
	float la = mod(ac + 0.5 * sector, sector) - 0.5 * sector;
	float pid = mod(floor((ac + 0.5 * sector) / sector), N);
	vec2 pq = vec2(cos(la), sin(la)) * rc - vec2(petal_radius, 0.0);

	float dP = d_lens(pq, lens_length, lens_width);
	float rq = length(pq);
	dP = min(dP, abs(rq - 0.115));                            // circle, outer
	dP = min(dP, abs(rq - 0.08));                             // circle, inner
	float pa = atan(pq.y, pq.x);
	float ds = fract(pa / TAU * 10.0) - 0.5;
	dP = min(dP, length(vec2(ds * TAU * 0.05 / 10.0, rq - 0.05))); // dotted ring
	D = min(D, dP);

	// small accent eyes between the petals + inner rings
	float lb = mod(ac, sector) - 0.5 * sector;
	vec2 bq = vec2(cos(lb), sin(lb)) * rc - vec2(0.40, 0.0);
	D = min(D, d_lens(bq, 0.14, 0.055));
	D = min(D, abs(rc - 0.27));
	D = min(D, abs(rc - 0.255));

	// ---- 5. Center ----
	D = min(D, abs(rc - 0.1));
	D = min(D, abs(rc - 0.07));
	float ca = atan(pc.y, pc.x);
	float cds = fract(ca / TAU * 14.0) - 0.5;
	D = min(D, length(vec2(cds * TAU * 0.04 / 14.0, rc - 0.04)));

	// ---- 6. Petal circles light up (pulsing), or all at once when charging ----
	float act = smoothstep(0.55, 0.85, 0.5 + 0.5 * sin(TIME * pulse_speed + hash11(pid + 3.0) * TAU));
	act = clamp(act + charge, 0.0, 1.0);
	float petal_fill = (1.0 - smoothstep(0.076, 0.084, rq)) * act;

	float center_act = clamp(0.5 + 0.5 * sin(TIME * pulse_speed * 0.7) + charge, 0.0, 1.0);
	float center_fill = (1.0 - smoothstep(0.036, 0.044, rc)) * center_act;

	// ---- 7. Turn distance field into stroke + glow ----
	float aa = max(fwidth(D), 0.0008);
	float wd = line_width * wmod;
	float core = 1.0 - smoothstep(wd - aa, wd + aa, D);
	float glow = exp(-D * glow_falloff) * glow_strength;
	float halo = exp(-D * glow_falloff * 0.2) * 0.12;

	// faint disc fill, slightly stronger toward the rim
	float disc = (1.0 - smoothstep(0.96, 0.985, r0)) * fill_alpha * (0.6 + 0.4 * r0);

	// ---- 8. Reveal: circle draws on from the center outward, with a bright front ----
	float visible = 1.0 - smoothstep(reveal - 0.06, reveal, r0);
	float front = exp(-abs(r0 - reveal) * 25.0) * (1.0 - smoothstep(1.0, 1.3, reveal));

	// ---- 9. Combine ----
	float boost = 1.0 + charge * 1.2;
	vec3 col = fill_color.rgb * disc;
	col += glow_color.rgb * (glow + halo) * boost;
	col += core_color.rgb * core * core_intensity * boost;
	col += core_color.rgb * (petal_fill + center_fill) * 1.8;
	col += glow_color.rgb * front;
	col = mix(col, vec3(2.0), flash);

	float alpha = max(core, glow * 0.9 + halo) + disc + (petal_fill + center_fill) * 0.8 + front * 0.4;
	alpha = clamp(alpha + flash, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha * visible;
}
