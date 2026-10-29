#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: Noise

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return value;
}

// MARK: Studio backdrop
//
// The room the car stands in: a wall lit by one raking source from the upper
// left, a floor that catches a stretched pool of that light, and fine grain to
// keep the falloff from banding. Top and bottom resolve back into the canvas
// colour so the stage has no seam with the page around it.

[[ stitchable ]] half4 studio(float2 position, half4 color, float2 size, float dark, float horizon, float3 canvas, float3 lit, float3 floorC) {
    float2 uv = position / size;

    // Raking wall light: brightest along a diagonal, falling off below it.
    float rake = uv.x * 0.55 + (1.0 - uv.y) * 0.25;
    float wall = smoothstep(0.05, 0.95, rake) * smoothstep(0.0, 0.5, uv.y) * smoothstep(horizon + 0.02, horizon - 0.42, uv.y);
    float3 col = mix(canvas, lit, wall * mix(0.85, 0.62, dark));

    // Floor: darker plane under the horizon with a stretched light pool.
    float below = smoothstep(horizon - 0.01, horizon + 0.05, uv.y);
    float depth = clamp((uv.y - horizon) / max(0.001, 1.0 - horizon), 0.0, 1.0);
    float2 pool = float2((uv.x - 0.56) / 0.62, (uv.y - horizon - 0.07) / 0.12);
    float poolLight = exp(-dot(pool, pool) * 1.6);
    float3 floorCol = mix(floorC, lit, poolLight * mix(0.55, 0.42, dark));
    floorCol = mix(floorCol, canvas, smoothstep(0.35, 1.0, depth));
    col = mix(col, floorCol, below);

    // Edges resolve into the page.
    float edge = smoothstep(0.0, 0.14, uv.y) * smoothstep(1.0, 0.86, uv.y);
    col = mix(canvas, col, edge);

    float grain = hash21(position + float2(1.9, 3.7)) - 0.5;
    col += grain * mix(0.018, 0.028, dark);

    return half4(half3(col), 1.0);
}

// MARK: Battery energy
//
// The filled part of the battery. Idle it is a calm sheet of the accent; while
// charging, bands of brighter current run through it toward the leading edge.

[[ stitchable ]] half4 energyFill(float2 position, half4 color, float2 size, float time, float flow, float3 base, float3 deep, float3 hot) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);

    float3 col = mix(base, deep, smoothstep(0.0, 1.0, uv.y) * 0.4);

    // Chevrons of current, pointing the way the energy travels. A little noise
    // keeps the fronts from marching in a perfectly even rank.
    float2 p = float2(uv.x * aspect, uv.y);
    float warp = fbm(p * 1.5 + float2(-time * 0.4, 0.0));
    float phase = (p.x + abs(p.y - 0.5) * 0.85) * 4.6 - time * 2.6 + warp * 1.4;
    float wave = 0.5 + 0.5 * sin(phase);
    float crest = pow(wave, 9.0);
    float trough = pow(1.0 - wave, 3.0);
    col = mix(col, deep, trough * 0.42 * flow);
    col = mix(col, hot, crest * 0.8 * flow);

    // A soft lip of light on the top edge, like a filled vessel.
    col = mix(col, hot, smoothstep(0.14, 0.0, uv.y) * 0.3);

    float grain = hash21(position + float2(1.3, 8.1)) - 0.5;
    col += grain * 0.025;

    return half4(half3(col) * color.a, color.a);
}

// MARK: Charge limit
//
// The limit marker is a membrane pinned at its two ends. When it is dragged its
// belly lags behind and then swings through, and everything that touches it
// follows that curve. `bar` is x at the pinned ends, top, bottom, half width.

static float limitCurve(float y, float4 bar, float lag, thread float &slope) {
    float span = max(bar.z - bar.y, 1.0);
    float t = clamp((y - bar.y) / span, 0.0, 1.0);
    slope = -lag * 3.14159 * cos(3.14159 * t) / span;
    return bar.x - lag * sin(3.14159 * t);
}

// Diagonal hatching for the span between the present level and the limit. Its
// leading edge is the membrane, and the stripes near it shear with the bow.
// edge: marker x, belly lag, bar top, bar bottom, all in this rectangle's space.
[[ stitchable ]] half4 plannedHatch(float2 position, half4 color, float time, float3 ink, float4 edge) {
    float slope;
    float curve = limitCurve(position.y, float4(edge.x, edge.z, edge.w, 0.0), edge.y, slope);
    float inside = smoothstep(curve + 0.6, curve - 0.6, position.x);
    float shear = (edge.x - curve) * smoothstep(edge.x - 90.0, edge.x, position.x);
    float d = (position.x + shear + position.y) / 9.0 - time * 0.6;
    float line = smoothstep(0.38, 0.5, abs(fract(d) - 0.5));
    float alpha = mix(0.06, 0.42, line) * color.a * inside;
    return half4(half3(ink) * alpha, alpha);
}

static float gooBox(float2 p, float2 half_, float radius) {
    float2 q = abs(p) - half_ + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

static float gooSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// Two shapes that come close run together instead of touching.
static float gooUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// The marker itself, as one body of ink: the bowed bar, the value flag that
// trails it, and the neck that stretches between them.
// flag: centre, half size. tilt: the flag's lean in radians.
[[ stitchable ]] half4 limitGoo(float2 position, half4 color, float2 origin, float4 bar, float4 flag, float2 motion, float3 ink, float3 grip) {
    float2 p = position - origin;
    float lag = motion.x, tilt = motion.y;

    float slope;
    float yc = clamp(p.y, bar.y, bar.z);
    float xc = limitCurve(yc, bar, lag, slope);
    float dBar = length(float2((p.x - xc) / sqrt(1.0 + slope * slope), p.y - yc)) - bar.w;

    float cs = cos(tilt), sn = sin(tilt);
    float2 f = p - flag.xy;
    f = float2(f.x * cs + f.y * sn, -f.x * sn + f.y * cs);
    float dFlag = gooBox(f, flag.zw, min(9.0, flag.w));

    // The neck thins as it is drawn out.
    float2 root = float2(bar.x, bar.y + 2.0);
    float2 foot = flag.xy + float2(-sn, cs) * flag.w;
    float neck = clamp(3.6 - 0.09 * length(foot - root), 1.5, 3.2);
    float dNeck = gooSegment(p, root, foot) - neck;

    float d = gooUnion(gooUnion(dBar, dNeck, 5.0), dFlag, 7.0);
    float alpha = smoothstep(0.7, -0.7, d);

    // Grip: three ridges that ride the curve.
    float mid = (bar.y + bar.z) * 0.5;
    float ridges = 0.0;
    for (int i = -1; i <= 1; i++) {
        float y = mid + float(i) * 6.0;
        float unused;
        float x = limitCurve(y, bar, lag, unused);
        ridges = max(ridges, smoothstep(1.5, 0.7, length(p - float2(x, y))));
    }
    float3 col = mix(ink, grip, 0.55 * ridges);
    return half4(half3(col) * alpha, alpha);
}

// MARK: Week
//
// The days a timed start runs on, as ink. Each chosen day is a drop; chosen
// days that sit next to each other run together into one bar, and when a day
// in the middle lets go the bar necks and parts. `early` and `late` carry how
// chosen each of the seven days is, 0 to 1.

[[ stitchable ]] half4 weekInk(float2 position, half4 color, float2 size, float4 early, float3 late, float radius, float3 ink) {
    float chosen[7] = { early.x, early.y, early.z, early.w, late.x, late.y, late.z };
    float slot = size.x / 7.0;
    float cy = size.y * 0.5;
    float d = 1000.0;
    for (int i = 0; i < 7; i++) {
        float2 here = float2(slot * (float(i) + 0.5), cy);
        float w = clamp(chosen[i], 0.0, 1.25);
        float before = i > 0 ? min(w, clamp(chosen[i - 1], 0.0, 1.0)) : 0.0;
        float after = i < 6 ? min(w, clamp(chosen[i + 1], 0.0, 1.0)) : 0.0;
        // A drop that is fully part of a bar must not swell it: the softening is
        // only for the moments a join is forming or letting go.
        float joined = min(max(before, after), 1.0);
        float soften = 0.02 + 5.0 * (1.0 - joined * joined);
        if (w > 0.02) d = gooUnion(d, length(position - here) - radius * w, soften);
        if (after > 0.02) {
            float2 next = float2(slot * (float(i) + 1.5), cy);
            // The bridge thins faster than the drops do, so it necks first.
            float bridge = gooSegment(position, here, next) - radius * after * after;
            d = gooUnion(d, bridge, 0.02 + 5.0 * (1.0 - after * after));
        }
    }
    float alpha = smoothstep(0.7, -0.7, d);
    return half4(half3(ink) * alpha, alpha);
}

// MARK: Time tape
//
// The ten minutes the climate runs before the ready time, drawn against the
// needle of the time tape: faint where the car starts, full where the cabin is
// ready, with air streaming toward the needle. Its leading edge is the needle's
// own curve. edge: needle x, belly lag, bar top, bar bottom.

[[ stitchable ]] half4 warmBand(float2 position, half4 color, float4 edge, float lead, float time, float3 base, float3 hot) {
    float slope;
    float curve = limitCurve(position.y, float4(edge.x, edge.z, edge.w, 0.0), edge.y, slope);
    float start = edge.x - lead;
    float inside = smoothstep(curve + 0.6, curve - 0.6, position.x) * smoothstep(start - 0.6, start + 0.6, position.x);
    if (inside <= 0.001) return half4(0.0);

    float rise = clamp((position.x - start) / max(curve - start, 1.0), 0.0, 1.0);
    float2 uv = float2((position.x - time * 26.0) * 0.02, position.y * 0.17 + sin(position.x * 0.05 + time * 0.8) * 0.25);
    float n = fbm(uv);
    float lines = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
    float3 col = mix(base, hot, clamp(lines * 0.8 * rise + rise * rise * 0.2, 0.0, 1.0));
    col += (hash21(position + float2(3.1, 7.7)) - 0.5) * 0.025;

    float alpha = inside * mix(0.2, 1.0, pow(rise, 0.8));
    return half4(half3(col) * alpha, alpha);
}

// MARK: Cabin air
//
// Streams of conditioned air moving through the cabin from the dashboard to the
// rear bench. `warmth` runs from -1 (cooling) to 1 (heating).

[[ stitchable ]] half4 airflow(float2 position, half4 color, float2 size, float time, float warmth, float strength) {
    float2 uv = position / size;

    // Streamlines, as in a wind tunnel: long threads that lean and wander as
    // they travel back through the cabin, over a faint body of moving air.
    float sway = sin(uv.y * 3.2 + time * 0.7) * 0.06 + sin(uv.y * 7.5 - time * 1.1) * 0.025;
    float2 p = float2((uv.x + sway) * 6.5, uv.y * 0.9 - time * 0.42);
    float n = fbm(p);
    float lines = (1.0 - smoothstep(0.0, 0.028, abs(n - 0.46)))
                + (1.0 - smoothstep(0.0, 0.022, abs(n - 0.58))) * 0.8;
    float haze = smoothstep(0.34, 0.66, fbm(p * 0.55 + float2(2.0, -time * 0.2)));

    // Air leaves the vents strong and thins toward the rear bench.
    float throwFade = smoothstep(0.0, 0.10, uv.y) * mix(1.0, 0.4, smoothstep(0.25, 1.0, uv.y));
    float sides = smoothstep(0.0, 0.16, uv.x) * smoothstep(1.0, 0.84, uv.x);

    float3 heat = mix(float3(1.0, 0.58, 0.20), float3(1.0, 0.84, 0.52), lines);
    float3 chill = mix(float3(0.42, 0.74, 0.94), float3(0.84, 0.96, 1.0), lines);
    float3 col = mix(chill, heat, smoothstep(-0.2, 0.2, warmth));

    float alpha = clamp((haze * 0.26 + lines * 0.6) * throwFade * sides * strength, 0.0, 1.0) * color.a;
    return half4(half3(col) * alpha, alpha);
}

// MARK: Ripple
//
// A single damped wave travelling out from a touch, after Apple's WWDC24
// "Create custom visual effects with SwiftUI" sample.

[[ stitchable ]] half4 ripple(float2 position, SwiftUI::Layer layer, float2 origin, float time, float amplitude, float frequency, float decay, float speed) {
    float distance = length(position - origin);
    float delay = distance / speed;
    float t = max(0.0, time - delay);
    float amount = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 direction = distance > 0.001 ? normalize(position - origin) : float2(0.0);
    half4 c = layer.sample(position + amount * direction);
    // Shade the crest and the trough so the wave reads on flat colour too,
    // where displacement alone would move nothing you could see.
    float shade = amount / max(amplitude, 0.001);
    c.rgb *= half(1.0 + 0.5 * shade);
    return c;
}

// MARK: Stale reading
//
// An ageing figure loses its top: the lower half stays solid, and from there upward
// it dissolves into a blur made of grain, each point drawn from a few scattered
// samples instead of a smooth average. `amount` runs from 0 (just reported,
// untouched) to 1 (an hour old or more).

[[ stitchable ]] half4 staleBlur(float2 position, SwiftUI::Layer layer, float2 size, float amount) {
    float up = 1.0 - clamp(position.y / max(size.y, 1.0), 0.0, 1.0);
    // The figures stand between about 0.09 and 0.73 of the line, foot to cap.
    float reach = smoothstep(0.4, 0.86, up) * amount;
    float radius = reach * 10.0;

    float2 cell = floor(position * 2.0);
    half4 sum = half4(0.0);
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float angle = hash21(cell + float2(fi * 7.3, 1.1)) * 6.2832;
        float dist = sqrt(hash21(cell + float2(2.7, fi * 3.9))) * radius;
        sum += layer.sample(position + float2(cos(angle), sin(angle)) * dist);
    }
    half4 c = sum / 6.0;

    // Speckle thickens with the blur, and the top thins out as it goes.
    float n = hash21(cell + float2(4.7, 1.3));
    float keep = mix(1.0, 0.5 + 0.5 * step(0.4, n), reach);
    keep *= 1.0 - 0.2 * reach;
    return c * half(keep);
}

// MARK: Lens wave
//
// A bead of clear glass that lies along the rim of the screen and travels it.
// Nothing here has a colour of its own: the bead bends what is under it, splits
// that bend a little between red and blue, and catches one thin line of light
// on its inner rim. Distances along the rim are measured from the top centre,
// the same on both sides, so one bead is always a mirrored pair.
//
// frame: top of the screen in layer space, corner radius, floor (where the
//        bead has thinned to nothing), unused
// bead:  head (distance along the rim), length, width, direction (1 away from
//        the top centre, -1 back toward it)
// rest:  film width, film reach along the rim, pull bulge width, clock

static float lensBead(float s, float4 bead, thread float &glint) {
    glint = 0.0;
    if (bead.z < 0.05) return 0.0;
    float nose = max(bead.z * 1.15, 1.0);
    float behind = (bead.x - s) * bead.w;
    if (behind < -nose || behind > bead.y) return 0.0;
    glint = exp(-(behind * behind) / (nose * nose * 2.4));
    if (behind < 0.0) {
        float q = behind / nose;
        return bead.z * sqrt(1.0 - q * q);
    }
    float q = behind / max(bead.y, 1.0);
    return bead.z * pow(1.0 - q, 1.7);
}

// Between the two beads the wave crosses the whole screen as a bend with no
// rim of its own: one swell and a fainter echo behind it. The middle lags the
// edges, the more the faster the beads travel, and catches up as they slow.
static float2 lensFront(float2 position, float4 bead, float top, float r, float sideStart, float e, float mirror, float hw, thread float &shade) {
    if (bead.z < 0.05) return float2(0.0);
    float amp = smoothstep(sideStart - 90.0, sideStart + 30.0, bead.x) * bead.z / 42.0;
    float sag = clamp((bead.y - 60.0) * 0.42, 0.0, 100.0) * bead.w;
    float front = top + r + (bead.x - sideStart) - sag * (1.0 - e * e);
    float x = (position.y - front) / 24.0;
    float swell = -x * exp(-0.5 * x * x) * 1.65;
    float xb = x + 2.7 * bead.w;
    swell += -xb * exp(-0.5 * xb * xb) * 0.5;
    float reach = 10.0 * amp * mix(0.5, 1.0, pow(e, 1.5));
    float slope = sag * 2.0 * e / hw * mirror;
    shade += swell * reach / 10.0;
    return normalize(float2(-slope, 1.0)) * reach * swell;
}

[[ stitchable ]] half4 lensWave(float2 position, SwiftUI::Layer layer, float2 size, float4 frame, float4 beadA, float4 beadB, float4 rest, float tone) {
    // The effect is also run on a margin around the layer, where sampling
    // would smear the layer's outermost pixels. Draw nothing there.
    if (position.x < 0.0 || position.y < 0.0 || position.x > size.x || position.y > size.y) return half4(0.0);

    float hw = size.x * 0.5;
    float r = min(frame.y, hw);
    float2 q = float2(abs(position.x - hw), position.y - frame.x);
    float mirror = position.x > hw ? 1.0 : -1.0;
    float sideStart = (hw - r) + r * 1.5708;
    // Everything thins out toward the floor of the stage rather than stopping.
    float fade = 1.0 - smoothstep(frame.z - 200.0, frame.z - 30.0, position.y);

    // Where this point sits against the rim: how deep in, how far along, and
    // which way is inward.
    float depth;
    float along;
    float2 inward;
    if (q.x > hw - r && q.y < r) {
        float2 v = q - float2(hw - r, r);
        float len = max(length(v), 0.001);
        depth = r - len;
        along = (hw - r) + r * clamp(atan2(v.x, -v.y), 0.0, 1.5708);
        inward = float2(-v.x * mirror, -v.y) / len;
    } else if (q.y < hw - q.x) {
        depth = q.y;
        along = q.x;
        inward = float2(0.0, 1.0);
    } else {
        depth = hw - q.x;
        along = sideStart + (q.y - r);
        inward = float2(-mirror, 0.0);
    }
    if (depth < 0.0) return layer.sample(position);

    float glintA, glintB;
    float wa = lensBead(along, beadA, glintA);
    float wb = lensBead(along, beadB, glintB);
    float wr = rest.x * (1.0 - smoothstep(rest.y * 0.4, rest.y, along));
    float wp = rest.z * exp(-(along * along) / (2.0 * 118.0 * 118.0));
    // Glass that meets glass runs together instead of overlapping.
    float w = pow(wa * wa * wa + wb * wb * wb + wr * wr * wr + wp * wp * wp, 1.0 / 3.0);
    // The surface is never quite still.
    w *= 1.0 + 0.045 * sin(along * 0.05 - rest.w * 4.2) * smoothstep(0.0, 70.0, along);
    w *= fade;

    float frontShade = 0.0;
    float e = clamp(q.x / hw, 0.0, 1.0);
    float2 shift = lensFront(position, beadA, frame.x, r, sideStart, e, mirror, hw, frontShade)
                 + lensFront(position, beadB, frame.x, r, sideStart, e, mirror, hw, frontShade);
    shift *= fade;
    frontShade *= fade;

    // The bead bends nothing at the screen edge, most just inside its inner
    // rim, and nothing again on the rim itself, so the picture stays whole.
    bool inBead = w >= 0.35 && depth <= w;
    float u = inBead ? depth / w : 0.0;
    float bend = inBead ? pow(u, 1.5) * (1.0 + 1.4 * u * u) * (1.0 - smoothstep(0.8, 1.0, u)) : 0.0;
    shift += -inward * min(w * 0.52 * bend, 26.0);

    if (dot(shift, shift) < 0.0004 && !inBead) return layer.sample(position);

    half4 mid = layer.sample(position + shift);
    half4 c = half4(layer.sample(position + shift * 0.84).r, mid.g, layer.sample(position + shift * 1.16).b, mid.a);
    // The swell lifts and lowers the light a little as it bends the picture.
    c.rgb *= half(1.0 + 0.08 * clamp(frontShade, -1.0, 1.0));
    if (!inBead) return c;

    // One light, above and a little to the left. Hairline tails carry none.
    float body = smoothstep(0.0, 7.0, w);
    float lit = mix(0.5, 1.0, clamp(dot(inward, normalize(float2(0.45, 0.9))), 0.0, 1.0));
    float rim = smoothstep(w, w - 0.9, depth) * smoothstep(w - 2.6, w - 1.0, depth);
    float glint = max(glintA * step(0.05, wa), glintB * step(0.05, wb));
    float shine = rim * (0.34 + 0.4 * glint) * lit * body;
    float thick = (1.0 - u) * (1.0 - u) * 0.03 * body;
    float shade = smoothstep(0.55, 0.98, u) * (1.0 - rim) * 0.07 * body;
    // Where the glass bends hardest it also gathers the light it bent.
    float caustic = bend * (0.045 + 0.05 * glint) * lit * body;

    if (tone > 0.0) {
        c.rgb = c.rgb + half3(half((shine + thick + caustic) * c.a));
    } else {
        // On a light page the rim reads as a fine dark line with light inside it.
        c.rgb = c.rgb * half(1.0 - shade * 1.6 - rim * 0.1 * body);
        c.rgb = mix(c.rgb, half3(c.a), half(shine * 0.55 + thick));
    }
    return c;
}
