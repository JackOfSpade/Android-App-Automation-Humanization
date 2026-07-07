Humanization Standard — Android App Automation
Status: normative reference. Single source of truth for making automated touch input on a physical Android phone indistinguishable from a human hand. Written to be implemented against: anyone told to "automate Android app X humanly" reads this, adopts the philosophy, and reuses the shared layers instead of inventing a per-app scheme.

Scope. Fixed platform, open app set. The target is always a physical Android device driven host-side over ADB (no on-device agent). The app is a variable — this standard is app-agnostic and must not bake in any one app's flow. What is not variable: it's a real touchscreen, so taps and swipes carry pressure, contact size, tool type, and hardware cadence, and those attributes are part of the fingerprint we reproduce.

Confidence taxonomy (put it on every claim that drives a decision): HIGH = official docs / reproducible behavior; MEDIUM = credible research, not app-confirmed; LOW = anecdote / reverse-engineering guess.

Authorization & ethics — non-negotiable. Humanized touch exists to reduce detectability; it's dual-use. Apply it only where authorized: your own accounts, sanctioned testing, research, or apps whose terms permit it. Automating a third-party app usually violates its terms, and this standard does not make that compliant — only lower-footprint, never safe or permitted. Settle the authorization question before the pressure-curve question.

1. Philosophy — the prime directives
Everything follows from six principles. When a case isn't covered, derive from these.

The device is the weak link, not the evasion. No pressure curve saves a rooted phone, an emulator, a datacenter IP, or an on-device automation helper. Get Layer 0 right first; it dominates every touch trick. (HIGH.)
Reduce footprint before you fake signals. The best synthetic touch is one that doesn't need to lie because it flows through the real kernel input pipeline. Prefer a genuine input path (a virtual HID digitizer) and observation without instrumentation (screencap + vision, not the accessibility tree) over injecting artifacts and hiding them.
Model the hand, don't randomize the machine. A human finger obeys motor control — Fitts's law, asymmetric velocity, correlated tremor, a pressure ramp, log-normal timing. Draw from the model that generated real getevent data, calibrated to measurements. uniform(a, b) is itself a tell — and a constant pressure is a louder one.
Behavior is a distribution, not a tap. Detection weights aggregates — action rate, the committing-action ratio, session length, inter-action cadence — more than any single gesture. A perfectly humanized tap is worthless if the rate and ratio are robotic. Cap and shape the aggregates (Layer 5).
Fail closed, never flail. A missed tap followed by blind retries is exactly the erratic burst detection loves. On any unexpected screen, stop and preserve evidence (Layer 6).
Passive ≪ Active. Observe mode (the human taps, we only read the screen) removes almost all behavioral evidence. Autonomous tapping is where the risk lives. Default to observe; treat auto as the deliberate, gated exception.
Corollary — determinism where it doesn't cost realism. Every motion/timing primitive takes an injectable RNG (rng=Random(seed)) so gestures are unit-testable and reproducible, defaulting to real randomness in production.

2. The touch attributes that matter (why Android is not click-automation)
A physical Android touchscreen reports, and MotionEvent exposes to any app, more than (x, y):

Attribute	MotionEvent / kernel source	What a synthetic input tap gets wrong
Pressure	getPressure() / ABS_MT_PRESSURE	constant or ~0; a real finger ramps up, plateaus, decays
Contact size	getSize() / ABS_MT_TOUCH_MAJOR	absent; a real contact has a finite, varying pad area
Tool type	getToolType() → TOOL_TYPE_FINGER	injection paths can look wrong / flagged
Report cadence	VSYNC-batched ~180 Hz digitizer	injected events arrive at the wrong rate/timing
Motion path	per-sample history in the MotionEvent	a straight, evenly-spaced, jitter-free line
Multi-touch/contact count	getPointerCount() / slots	a single teleported point
The consequence: the goal on Android is not "move the pointer nicely," it is to emit a per-sample touch stream (t, x, y, pressure, size, tip) that reproduces all of the above — for both taps and swipes — and to deliver it through a path that carries pressure/size to the kernel. That is Layers 1 and 3, and it's why Android humanization is deeper than desktop/web click automation. (Whether a given app reads pressure/size is MEDIUM; that a real digitizer produces them is HIGH — so we reproduce them regardless.)

3. The layered model
Layer 6  Verification & fail-closed     "did the screen change? if not, HALT"
Layer 5  Behavioral hygiene             rate caps, committing-action ratio, session shape
Layer 4  Timing realism                 log-normal delays, per-decision think time
Layer 3  Touch kinematics               Fitts + arc-length Bézier + OU tremor + pressure/size ramp
Layer 2  Perception w/o footprint       screencap + vision (NO accessibility tree)
Layer 1  Transport authenticity         virtual HID digitizer (pressure-carrying) over stock tooling
Layer 0  Device & identity              physical stock phone, residential IP, isolated account
─────────────────────────────────────────────────────────────────────────────
         ↑ higher layers are worthless if a lower layer is compromised ↑
Layers 3–5 are pure, app-independent modules reused verbatim for every app. A new app supplies only its perception (Layer 2) and action-location glue; it inherits the rest. That reuse is what lets the standard improve "as one."

4. The layers in detail
Layer 0 — Device & identity (foundation)
Owns nothing in code; gates everything.

Physical, stock, unrooted, Play-certified phone. Passes Play Integrity MEETS_DEVICE_INTEGRITY (and STRONG with a recent security patch); an emulator/AVD cannot — no hardware root-of-trust. No root, no bootloader unlock, no custom ROM. (HIGH.)
No on-device automation footprint. Do not install uiautomator2 / atx-agent / Appium helper APKs, and do not enable an accessibility service for automation. They trip Play Integrity appAccessRiskVerdict (UNKNOWN_CONTROLLING) even in read-only observe mode, and apps can enumerate accessibility services via getEnabledAccessibilityServiceList. Drive host-side only. (Google API HIGH; app-consumes-it MEDIUM.)
Residential network, no VPN/proxy/datacenter, for install, signup, verification, and every session; keep locale/timezone/geo coherent with the IP. (HIGH that datacenter/VPN is penalized; scoring LOW.)
Identity isolation. An account separated from anything you value, with a real (non-VoIP) number — because soft-bans/shadow-throttling are silent and unconfirmable, and bans can federate across a provider's apps via device/photo/face/phone/payment hashes. Autonomous use is only sane on a disposable identity. (HIGH for federation where documented.)
Portability note: if a target app runs no server-side integrity/behavioral checks, Layer 0 relaxes — but confirm which gates apply (§7) before assuming you can skip it. Don't guess.

Layer 1 — Transport authenticity (pressure-carrying input)
Principle 2 in code: deliver touches through the real kernel input pipeline, carrying pressure and size, so there's no injection artifact to hide.

Preferred: a non-root virtual HID touchscreen. Create a virtual multitouch digitizer through the stock /system/bin/hid tool over /dev/uhid (writable by the unprivileged shell domain — no root, no installed helper). Events flow through the genuine kernel input pipeline: TOOL_TYPE_FINGER, variable pressure, VSYNC-batched, not injection-flagged. This is strictly better than adb shell input tap/swipe, which is a synthetic injection with no pressure.
The HID descriptor must carry pressure. Single-finger multitouch digitizer with Tip Switch / Confidence / Contact ID / X / Y / Tip Pressure (0..255) / Contact Count. Build X/Y logical maxima from the live screen size so device coordinates map 1:1 to pixels on any resolution. Omit the Contact-Count-Maximum feature report — it triggers a kernel GET_FEATURE the HID stream can't answer and kills the device mid-enumeration.
Delivery: per-gesture file. hid <file> registers the device, plays register → enumerate-delay → report/delay stream → flush-delay, then destroys it at EOF (a persistent device needs a held-open FIFO, which SELinux denies the shell domain). Cost: one re-enumeration per gesture, invisible to apps. Serialize gestures so a concurrent writer can't truncate a file another gesture is mid-read on.
Graceful, explicit degradation. If /system/bin/hid is absent, raise a distinct "UHID unavailable" and fall back to the adb input transport — still functional, but pressure/size are lost; record that the fidelity dropped. A touch_backend: auto|uhid|adb config knob forces the choice.
Text entry goes through ADB (input text / clipboard-paste), not simulated per-key taps, unless a specific app reads key timing.
Layer 2 — Perception without footprint
Reading the accessibility tree or running an on-device inspector is the footprint Layer 0 forbids. Instead:

Capture, don't inspect. adb exec-out screencap frames only. Dedupe consecutive frames by a downsampled signature (e.g. 24×24 grayscale) to tell "the screen advanced" from "frame noise" with no UI hierarchy. A repeated signature = the screen stopped changing (reached the bottom / a static screen).
Locate actions by vision, not fixed coordinates. Template-match the glyph/label (a button, an icon, a modal's text) with normalized cross-correlation + non-max suppression, filtered by screen region. Controls move (banners, dynamic layouts, per-item heights) and can blend into their background — a fixed screen-fraction is unreliable. Keep a calibrated fixed-fraction fallback for when vision misses (degraded, but better than not acting).
Region-split diffing distinguishes kinds of change: a bottom sheet sliding up (bottom region changes, top stays) vs a full screen transition (top changes too). This is how observe mode infers the human's tap-vs-scroll-vs-transition from pixels alone.
Degrade safely, never silently. If frames won't decode (missing image libs) or the device wedges (empty/truncated screencaps), refuse to run rather than continue blind — a blind run mislabels manual scrolls and corrupts any data you're collecting.
Layer 3 — Touch kinematics (taps and swipes, with pressure)
Principle 3 in its fullest form. A pure, transport-agnostic synthesizer emits the per-sample stream (t, x, y, pressure, size, tip) that Layer 1 turns into HID reports. Calibrate it to real getevent -lt traces measured off a genuine human on the reference phone (report rate, samples/gesture, raw pressure min/mean/max, contact-major range, dwell/reaction times). No device access, fully unit-testable, every function takes rng.

The models, and why each replaces the naive choice:

Component	Model	Replaces	Why
Swipe duration	Fitts (Shannon): MT = a + b·log₂(D/W + 1)	constant / linear time	Move time scales with index of difficulty, not distance alone
Swipe path	Cubic Bézier, control points pushed perpendicular by a random fraction of chord length, reparameterized by arc length	a straight line	A finger bows; arc-length reparam makes sample spacing follow speed, not the curve parameter
Swipe velocity	Asymmetric lognormal profile, peak early (~35% of stroke), longer deceleration	symmetric ease-in-out	Human strokes accelerate fast, decelerate slow
Tremor (both)	Ornstein–Uhlenbeck, mean-reverting/temporally correlated, amplitude scaled by instantaneous speed (signal-dependent noise, Harris–Wolpert)	white-noise jitter	Real tremor is correlated frame-to-frame and grows with speed
Pressure/size (both)	Beta-function ramp uᵅ(1−u)ᵝ, rise→plateau→decay, with a nonzero floor while the finger is down	constant / zero pressure	A capacitive digitizer only reports contact above a detection threshold — an in-contact frame is never exactly 0; only the explicit release is
Tap dwell	lognormal down→up (median ~130 ms), clamped	fixed press duration	Real press dwell is right-skewed
Tap micro-slip	damped slide from the impact point + a pressure pulse	a stationary point	A finger settles and slides slightly on contact
Endpoints (both)	exact start/end, no jitter on first/last sample	jitter everywhere	The finger lands on the target; only the transit is noisy
Both taps and swipes carry the full pressure/size envelope — that's the Android-specific heart of this layer. A tap is not a zero-length event; it's a short dwell with a pressure pulse. A swipe is a curved, speed-varying path whose pressure rises and falls across the stroke.

Rule for extending: any new gesture (long-press, fling, pinch) derives its parameters from measured getevent data, stays pure + rng-injectable, and records its calibration source in the parameter table (§8). No hand-tuned constants without a measurement.

Layer 4 — Timing realism
Every wait is an anchor delay × a log-normal multiplier (seconds · exp(N(0,σ)·σ), σ≈0.22), not a uniform range — giving an organic long tail (usually near the anchor, occasionally much longer, never negative). Two variants:

human_delay(seconds) — may be shorter or longer. For ordinary pauses (between actions, settle waits, per-step moves).
human_cooldown(seconds) — never below the anchor (uses abs of the normal sample). For minimum waits and backoffs.
Per-decision "think time" is a distinct, higher-level model: a shifted-lognormal whose parameters differ by decision type — e.g. a committing action is often a faster reaction than a rejecting one — matching measured reaction-time asymmetry. Measure each decision type's real reaction distribution; don't reuse one anchor for all.

Rule: no bare sleep(constant) and no uniform delay on any app-facing action path — route it through the timing layer. Short internal poll cadences the app never sees (a screenshot loop) are exempt.

Layer 5 — Behavioral hygiene
Principle 4. Applies to auto mode only (observe = the human's own taps, never capped):

Volume caps per session and per day.
Committing-action ratio cap — the load-bearing one. Whatever tap the app treats as a conversion (a like, follow, submit, purchase) is the action a bot over-produces; an anomalous ratio of it is often a more reliable bot signal than raw volume. Cap it below total actions to hold the ratio human. (HIGH that ratio is used; thresholds LOW — stay conservative.)
When a cap is hit, stop the run — don't substitute a different action to keep going; that both looks robotic and corrupts any labels/data.
Session shape: keep sessions in a human-plausible window and let Layer 4 spread taps out; don't burst.
Checks run before each autonomous action. New apps reuse the same limiter; only the numbers move (per-app config).

Layer 6 — Verification & fail-closed
Principle 5. After every autonomous action the screen must change (a new item, a confirmation sheet). If it doesn't — even after a short settle — the tap missed or the app is in an unknown state → raise and HALT, preserving debug evidence, not retry blindly.

Generic progress check: the screen advanced (screencap diff over threshold).
Semantic end-state check: verify the specific expected result (e.g. a confirmation sheet and any upsell/intercept modal are gone and the deck moved off the pre-tap item). A bare change-check can be spoofed by an unrelated animation.
Distinguish a clean stop from an unexpected halt. A clean stop (DriverClosed — USB/ADB dropped, or the human closed the app) → flush buffered work, restart-safe. An unexpected halt (stuck screen, missed tap, unknown modal) → stop, snapshot the screen, keep logs. Never let the second masquerade as the first.
Silent debug log (per-run action journal + before/after screencaps on any anomaly) makes every halt reconstructable offline at ~no runtime cost.
5. Cross-cutting principles
Config over constants. No hardcoded ADB paths, screen-fraction coordinates, thresholds, or caps in code — everything in config, overridable per app. Code ships calibrated defaults; live values are verified on-device.
Purity + injectable RNG = testability. Layers 3–5 are pure, no I/O, seedable; unit-tested offline. Only transport (Layer 1) and perception (Layer 2) need real hardware.
Screencap, not accessibility; vision, not hierarchy. Restated because it's the most-violated rule under time pressure.
Detection tricks are fragile. Integrity policy tightens; on-device signals change. Prefer structural choices (real phone, genuine input path, no helper) over clever ones; re-verify before relying on any single trick (§9).
Mark unverified coordinates in code. Where a screen-fraction/threshold is best-effort from a partial UI map, flag it inline (LIVE-VERIFY). Those markers are a calibration to-do list, not decoration — resolve them against a real session before trusting auto mode.
6. Implementation contract — adding a new app
Keep the driver interface small so the orchestrator stays app-agnostic and all six layers are inherited. For app X you write only what's app-specific:

You must provide:

open_session() — launch/attach to the app and reach the actionable screen.
capture_state() — Layer 2: perceive via screencap + vision. No accessibility tree.
act_primary(payload?, item_index?) / act_secondary() — vision-locate the action (L2), then tap/swipe through the shared HID transport (L1) using shared kinematics (L3) + timing (L4).
is_exhausted() — empty/end-state detection (usually a template match).
accepts_payload — whether the app attaches text at action time (gates upstream work in auto mode).
(observe mode) wait_for_decision() — infer the human's tap/scroll/transition from region-split frame diffs (L2).
You reuse unchanged: the timing layer (L4), the touch-kinematics synthesizer (L3), the UHID/ADB transport (L1), the rate limiter (L5), the verify_*/fail-closed pattern (L6), and the config schema.

You must not: add a bespoke delay scheme, hand-roll gesture jitter, drop pressure to a constant, read the accessibility tree, install an on-device helper, or hardcode coordinates. If you're doing any of these, the reusable layer already exists — use it, or improve it in place so every app benefits.

7. Portability checklist for a new app
not done
Threat model. Does the app run Play Integrity? Behavioral analytics? A named anti-bot SDK? Does it read MotionEvent pressure/size? Record with confidence levels; mark unknowns and design conservatively.
not done
Layer 0. Device/network/identity posture meets the bar the threat model implies (or document why a layer is skippable).
not done
Layer 1. UHID available (/system/bin/hid present)? If not, adb input fallback — note that pressure/size are lost.
not done
Layer 2. screencap working; collect glyph/label templates for every action and modal; set change thresholds by measurement.
not done
Layer 3/4. Reuse as-is; re-measure only if the phone's digitizer or the app's cadence differs materially from the reference.
not done
Layer 5. Conservative per-app caps; get the committing-action ratio right first.
not done
Layer 6. Wire verify_* for each action's expected end-state; enable the debug log.
not done
Resolve every LIVE-VERIFY against a real session before trusting auto mode.
not done
Observe before auto. Validate in observe mode; flip to autonomous only once observe is clean.
8. Parameter reference (reference calibration — recalibrate per phone)
Reference values from one real phone + human; starting points, re-measure (§9) for a new device. Changing a shared value changes every app — justify with a measurement.

Parameter	Reference	Meaning / source
Timing σ	0.22	log-normal spread around any anchor delay
Report rate	~180 Hz	match the measured digitizer rate (getevent)
Fitts a, b	0.11, 0.17	Shannon swipe movement time, touch-typical
Default target width	180 px	Fitts W for a typical control
Velocity peak / σ	0.35, 0.18	lognormal tangential-velocity profile
Tremor θ / amplitude	22.0, 2.2 px	OU mean-reversion; base jitter (speed-scaled 0.4–1.0×)
Pressure α, β	1.25, 0.85	beta ramp shape (rise→decay)
Pressure peak / floor	0.95 / 0.22	normalized; floor ≈ 56/255 digitizer detection threshold
Contact size peak	0.55	normalized contact-major (ABS_MT_TOUCH_MAJOR)
Tap dwell median / σ	0.13 s, 0.25	lognormal, clamped 0.04–0.35 s
Tap micro-slip	2.5 px	finger-pad slide on impact
Think time (committing)	shift 1.2, μ 0.65, σ 0.35 → ~3.2 s	faster reaction
Think time (rejecting)	shift 1.8, μ 1.45, σ 0.42 → ~6.9 s	slower reaction
Read/consider dwell	~1.1 s	per-item consideration pause
State-change threshold	9.0	mean grayscale delta (0..255, 24×24) = "region changed"
UHID enumerate / flush	700 ms / 150 ms	per-gesture device re-enumeration + flush
Volume caps	~30 / run, ~50 / day	conservative starting caps
Committing-action cap	~15 / run	holds the committing-action ratio human (key cap)
Between-action anchor	~3.5 s	typical inter-action pause
(Record provenance — device, date, method — next to the constants. Undocumented constants rot.)

9. Anti-patterns (do not ship these)
❌ sleep(2) / uniform(1, 3) on an action path → use the timing layer.
❌ adb shell input tap/swipe as the primary transport → it's synthetic-flagged and carries no pressure/size; UHID is genuine kernel input.
❌ Constant or zero pressure while the finger is down → physically impossible on a capacitive sensor; use the beta ramp with a floor, on both taps and swipes.
❌ Reading the accessibility tree / installing uiautomator2 / any on-device helper → the exact footprint Layer 0 forbids, flagged even in observe.
❌ Fixed-coordinate taps as the primary locator → controls move; vision-match the glyph, keep the coord only as fallback.
❌ White-noise jitter or a symmetric ease on swipes → correlated tremor + asymmetric velocity are the point.
❌ Blind retry after a missed tap → fail closed (Layer 6).
❌ High volume with a skewed committing-action ratio → often the most reliable bot signal.
❌ Hardcoded coords/thresholds/caps → config, per app.
❌ Emulator / VPN / datacenter IP / rooted phone for an integrity-gated app.
❌ Autonomous action on an account you care about → soft-bans are silent; isolated identity only.
10. Calibration protocol (deriving numbers for a new phone)
The models are general; the constants are device-specific.

Capture real input. With a human using the app, record getevent -lt for a representative set of taps and swipes. Extract: report rate (Hz), samples/gesture, raw pressure min/mean/max (ABS_MT_PRESSURE), contact-major range (ABS_MT_TOUCH_MAJOR), dwell and reaction times.
Fit the profiles. Set the report rate to measured; pressure floor/peak from raw min/mean; tap dwell from the dwell distribution; think-time params from the reaction-time distribution per decision type.
Set vision thresholds by measuring frame deltas for real transitions vs noise; pick the change threshold between them.
Collect templates at the phone's native resolution for every action glyph/label and modal.
Record provenance — date, device, method — next to the constants.
11. Improving this standard (evolving "as one")
The shared layers are the leverage point: a better model here upgrades every app at once.

Change the shared module, not a per-app copy. If an app needs different behavior, first ask whether it belongs in the shared layer as a parameter. Bespoke per-app humanization is a smell.
Back every constant change with a measurement (§10) and update §8's provenance. No vibes-based tuning.
Keep the threat model in sync. Record the vector each defense answers and its confidence; when a vector is disproven or a signal changes, update the standard and any affected re-check trigger.
Preserve testability. Any change to Layers 3–5 stays pure and rng-injectable, with offline tests.
Re-check triggers. Play Integrity policy changes (DEVICE vs STRONG); a target's actual anti-bot SDK becoming known; measured drift in a phone's digitizer; new evidence on whether apps read pressure/size. When one fires, update the standard first, then the drivers.
Prescriptive for everything built against it. When an implementation and this document disagree, that's a bug in one of them — reconcile, don't ignore.
