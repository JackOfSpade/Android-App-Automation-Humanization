# Humanization Standard — UI Automation
Status: normative reference. This is the single source of truth for how to make automated UI interaction indistinguishable from a human. It is written to be implemented against: anyone (or any AI) told to "automate app/target X humanly" reads this, adopts the philosophy, and reuses the shared layers instead of inventing a per-target humanization scheme.

**Scope. Any interactive target — mobile app, desktop app, or web — driven by any transport. The philosophy (§1) and the layered model (§2–§3) are platform-agnostic. Concrete transports (kernel input, browser engine, OS input APIs) appear only as example bindings; the spine does not depend on them.**

**Confidence taxonomy (use it on every claim that drives a decision): HIGH = official docs / reproducible behavior; MEDIUM = credible research, not target-confirmed; LOW = anecdote / reverse-engineering guess.**

**Authorization & ethics — non-negotiable. Humanized automation exists to reduce detectability. That is powerful and dual-use. Apply it only where you are authorized: your own accounts, sanctioned testing, research, or systems whose terms permit it. Automating a third party's service typically violates its terms, and this standard does not make that compliant — it only makes the automation lower-footprint, never safe or permitted. Do not use it to evade controls at scale, to harm a service, or against anyone who hasn't consented. Get the authorization question right before you get the timing distribution right.**


## 1. Philosophy — the prime directives
Everything downstream follows from six principles. When a situation isn't covered by a specific rule, derive the answer from these.

The environment is the weak link, not the evasion. No amount of humanized motion saves a compromised environment — a virtualized/rooted device, a datacenter IP, an instrumented runtime, an injected agent. Get Layer 0 (environment + identity) right first; it dominates every behavioral trick. (HIGH — the most robust finding in this space.)
Reduce footprint before you fake signals. The best synthetic input is the one that doesn't need to lie because it flows through a genuine path. Prefer authentic transports (real input pipeline, real client) and observation without instrumentation (capture + perception, not a hooked accessibility/inspection API) over injecting artifacts and then hiding them.
Model the human, don't randomize the machine. Humans are not uniform noise. Real motor control and cognition have structure — Fitts's law, asymmetric velocity, correlated tremor, log-normal timing, decision-dependent latency. Draw from the model that generated the real data, calibrated to measurements. A flat uniform(a, b) is itself a tell.
Behavior is a distribution, not an action. Detection weights aggregate patterns — action rate, action-type ratio, session length, inter-action cadence — far more than any single gesture. Humanizing one click is worthless if the rate and ratio are robotic. Cap and shape the aggregates (Layer 5).
Fail closed, never flail. A missed action followed by blind retries produces exactly the erratic, impossible-for-a-human burst that detection loves. On any unexpected state, stop and preserve evidence rather than thrash (Layer 6).
Passive ≪ Active. Human-in-the-loop / observe-only modes (the human acts, you only read) remove almost all behavioral evidence. Autonomous action is where the risk lives. Default to passive; treat active/autonomous as the deliberate, gated exception.
**Corollary — determinism where it doesn't cost realism. Every motion/timing primitive accepts an injectable RNG (e.g. rng=Random(seed)) so it is unit-testable and reproducible, while defaulting to real randomness in production. Humanization must never become untestable.**


## 2. The layered model
Humanization is a stack. Each layer is independently ownable, testable, and improvable — and shared across every target except where the transport differs. A new target supplies only its perception and action-location glue; it inherits the rest.


### Layer 6  Verification & fail-closed     "did the action land? if not, HALT"

### Layer 5  Behavioral hygiene             rate caps, action-type ratio, session shape

### Layer 4  Timing realism                 log-normal delays, per-decision think time

### Layer 3  Motion realism                 Fitts + Bézier + correlated tremor + dynamic pressure

### Layer 2  Perception w/o footprint       capture + vision (NO instrumented inspection API)

### Layer 1  Transport authenticity         genuine input path / real client (no injected agent)

### Layer 0  Environment & identity         genuine environment, trusted network, isolated identity
─────────────────────────────────────────────────────────────────────────────
         ↑ higher layers are worthless if a lower layer is compromised ↑
**Example bindings (the same layers, three transports — none is the spine):**

Layer	Mobile (native app)	Web (browser)	Desktop (native app)
1 Transport	virtual HID input device via the OS's stock input stack	stealth-patched engine + real browser binary	OS-level input injection at the driver layer, not app-scripting
2 Perception	screen capture + template/OCR vision	DOM selectors (or vision if the DOM is instrumented-detectable)	screen capture + vision
3–5	shared, unchanged	shared, unchanged	shared, unchanged
6 Verification	screen-diff end-state check	DOM/visual end-state check	screen-diff end-state check
Layers 3–5 are pure, transport-independent modules reused verbatim everywhere. That reuse is what lets the standard improve "as one": a better model in a shared layer upgrades every target at once.


## 3. The layers in detail

### Layer 0 — Environment & identity (foundation)
Owns nothing in code; gates everything. The rules that generalize to any target with server-side integrity/behavioral checks:

Genuine, uncompromised environment. Passes whatever platform attestation exists (device integrity, remote attestation, TLS/JA3 fingerprint coherence). A virtualized, rooted/jailbroken, or emulated environment is frequently the single hardest gate to pass. (HIGH where attestation exists.)
No instrumentation footprint on the target host. Do not install an on-device automation agent, an inspection server, or an accessibility/scripting service the target can enumerate — many platforms flag these even in read-only mode. Drive from outside the target's trust boundary. (HIGH that such agents are detectable; whether a given target consumes the signal is MEDIUM.)
Trusted network. Residential/native network, not datacenter/VPN/proxy, for every phase (setup, verification, every session), and keep locale/timezone/geo coherent with the IP. (HIGH that datacenter/VPN is penalized; exact scoring LOW.)
Identity isolation. An account/identity separated from anything you value — because soft-bans (silent throttling) are often unconfirmable, and enforcement can federate across a provider's properties via device/network/payment/biometric hashes. Autonomous use is only sane on a disposable identity. (HIGH for federation where documented.)
**Portability note: if a target has no server-side integrity/behavioral checks, Layer 0 collapses to "don't do anything obviously idiotic." Confirm which gates actually apply (§6) before assuming you can skip it — don't guess.**


### Layer 1 — Transport authenticity
**Principle 2 in code: deliver input through a path the target can't distinguish from genuine, so there's no injection artifact to hide.**

Prefer a genuine input pipeline over a scripting/injection API. Input that flows through the real OS/kernel input stack (e.g. a virtual HID device created through a stock, unprivileged mechanism) arrives with authentic device semantics — real pointer type, variable pressure, hardware-batched timing — and is not injection-flagged, unlike a high-level "inject tap/click" call.
For browsers: use a stealth-patched automation engine (avoid the CDP/Runtime.enable class of leaks) driving a real browser binary (not a bundled/headless build with render and global tells), disable the automation flags (navigator.webdriver et al.), and inject no page artifacts (init scripts, custom globals, overlay DOM) — anything you add is readable by any page script.
Always ask: "what artifact does this transport leave that a target script can read?" — and eliminate it at the source before masking it.
Degrade explicitly, never silently. If the authentic transport is unavailable, fall back to a lower-fidelity one and record that the fidelity dropped; don't pretend nothing changed.
Serialize shared-resource gestures so concurrent actions can't corrupt each other's delivery.

### Layer 2 — Perception without footprint
**Principle 2 on the read side. Reading state through an instrumented inspection API is the footprint Layer 0 forbids. Instead:**

Capture, don't inspect. Take screenshots/frames. Dedupe consecutive frames by a downsampled signature so you can tell "state advanced" from "frame noise" without any inspection tree. A repeated signature means the screen stopped changing (reached an end / a static screen).
Locate actions by vision, not fixed coordinates. Template-match or OCR the target glyph/label (with normalized cross-correlation + non-max suppression), filtered by region. Controls move (banners, dynamic layouts, responsive reflow) and a control can blend into its background — a fixed coordinate is unreliable. Keep a calibrated fixed-coordinate fallback for when vision misses (degraded, but better than not acting).
Region-split diffing distinguishes kinds of change (e.g. a sheet sliding up = bottom region changes, top stays; vs a full transition = whole frame changes). This is how a passive/observe mode infers the human's action from pixels alone.
Degrade safely, never silently. If frames won't decode or the capture is wedged, refuse to run rather than continue blind — a blind run mislabels state and corrupts any data you're collecting.

### Layer 3 — Motion realism
**Principle 3 in its fullest form. A pure, transport-agnostic gesture synthesizer emits a per-sample stream (t, x, y, pressure, size, contact) that Layer 1 turns into input reports. Calibrate it to real input traces measured off a genuine human on the reference device (sample rate, samples/gesture, pressure min/mean/max, contact size, dwell/reaction times). No I/O, fully unit-testable, every function takes an rng.**

The models, and why each replaces the naive choice:

Component	Model	Replaces	Why
Movement duration	Fitts (Shannon): MT = a + b·log₂(D/W + 1)	constant / linear time	Real move time scales with index of difficulty, not distance alone
Path	Cubic Bézier, control points pushed perpendicular by a random fraction of chord length, reparameterized by arc length	a straight line	A limb bows; arc-length reparam makes sample spacing follow speed, not the curve parameter
Velocity	Asymmetric lognormal profile, peak early (~35% of MT), longer deceleration	symmetric ease-in-out	Human strokes accelerate fast, decelerate slow — the profile is right-skewed
Tremor	Ornstein–Uhlenbeck (mean-reverting, temporally correlated) with speed-dependent amplitude (signal-dependent noise, per Harris–Wolpert)	white-noise jitter	Real tremor is correlated frame-to-frame and grows with speed; white noise is uncorrelated and detectable
Pressure / size	Beta-function ramp uᵅ(1−u)ᵝ, rise→plateau→decay, with a nonzero floor while in contact	constant / zero pressure	A capacitive sensor only reports contact above a threshold — an in-contact frame is never exactly 0; only release is
Discrete press (tap/click)	lognormal dwell + damped micro-slip from the impact point + a pressure pulse	fixed-duration press	A finger/click settles and slides slightly on contact
Endpoints	exact start/end, no jitter on first/last sample	jitter everywhere	The pointer lands on the target; only the transit is noisy
**Rule for extending: any new gesture derives its parameters from measured data, stays pure + rng-injectable, and records its calibration source in the parameter table (§7). No hand-tuned constants without a measurement.**

(Web/desktop pointer variant: a quadratic/cubic-Bézier cursor path with a slight overshoot, jittered — not dead-center — target point, and log-normal delays between micro-moves. Same principle, coarser transport.)


### Layer 4 — Timing realism
Every wait is an anchor delay × a log-normal multiplier (seconds · exp(N(0,σ)·σ), σ≈0.22), not a uniform range. This gives an organic long tail — usually near the anchor, occasionally much longer, never negative — which a bounded uniform can't. Two variants:

human_delay(seconds) — may be shorter or longer than the anchor. For ordinary pauses (between actions, settle waits, per-step moves).
human_cooldown(seconds) — never below the anchor (use abs of the normal sample). For minimum waits and backoffs.
Per-decision "think time" is a distinct, higher-level model: a shifted-lognormal whose parameters differ by decision type — e.g. an affirmative action is a faster reaction than a rejecting one — matching measured reaction-time asymmetry. When adding a decision type, measure its real reaction-time distribution; don't reuse one anchor for all.

**Rule: no bare sleep(constant) and no uniform delay on any target-facing action path — route it through the timing layer. Short internal poll cadences the target never sees (e.g. a screenshot loop) are exempt.**


### Layer 5 — Behavioral hygiene
**Principle 4. Applies to active mode only (passive/observe = the human's own actions, never capped). Tune caps from research/measurement, not vibes:**

Volume caps per session and per day.
Action-type ratio cap — usually the load-bearing one. Whatever the "committing" action is (the one a bot over-produces), an anomalous ratio of it is often a more reliable bot signal than raw volume. Cap the committing action below total actions to hold the ratio in a human range. (HIGH that ratio is used; exact thresholds LOW — stay conservative.)
When a cap is hit, stop — do not substitute a different action to keep going; that both looks robotic and corrupts any labels/data you're collecting.
Session shape: keep sessions in a human-plausible window and let Layer 4 spread actions out; don't burst.
Checks run before each autonomous action. New targets reuse the same limiter; only the numbers move (per-target config).


### Layer 6 — Verification & fail-closed
**Principle 5. After every autonomous action the observable state must change (a transition, a confirmation). If it doesn't — even after a short settle — the action missed or the target is in an unknown state. The response is to raise and HALT, preserving debug evidence, not to retry blindly.**

**Generic progress check: "the state advanced."**
**Semantic end-state check: verify the specific expected result (e.g. the confirmation dialog is gone and any upsell/intercept modal is gone and the view moved off the pre-action item). A bare change-check can be spoofed by an unrelated animation.**
Distinguish a clean stop from an unexpected halt. A clean stop (the human closed the target / the transport dropped) → flush buffered work, restart-safe. An unexpected halt (stuck state, missed action, unknown modal) → stop, snapshot the state, keep logs. Never let the second masquerade as the first.
Silent debug log (per-run action journal + before/after captures on any anomaly). Costs nothing at runtime and is the difference between "diagnosable" and "mystery."

## 4. Cross-cutting principles
**Config over constants. No hardcoded paths, coordinates, thresholds, or caps in code — everything lives in config, overridable per target. Code ships calibrated defaults; live values are verified against a real session. This is what lets the standard improve "as one."**
**Purity + injectable RNG = testability. Layers 3–5 are pure functions with no I/O; all randomness is seedable. Everything environment-independent is unit-testable offline; only transport and perception need real hardware.**
**Capture, not inspection; vision, not hierarchy. Restated because it's the most-violated rule when someone "just wants it working fast."**
**Detection tricks are fragile. Specific evasions get patched (engine leaks, attestation policy tightening). Any single trick can evaporate — re-verify before relying on it (§9), and prefer structural choices (genuine environment, real client, small footprint) over clever ones.**
**Mark unverified assumptions in the code. Where a coordinate/threshold is best-effort from a partial map, say so inline (a LIVE-VERIFY marker). Those markers are a to-do list for on-target calibration, not decoration.**

## 5. Implementation contract — adding a new target
Keep the driver interface small so the orchestrator stays target-agnostic and all six layers are inherited. To add target X you write only what's genuinely target-specific:

**You must provide:**

open_session() — attach to the target and reach the actionable screen.
capture_state() — Layer 2: perceive state via capture + vision. No instrumented inspection API.
act_primary(payload?, item_index?) / act_secondary() — locate the action by vision (L2), then act through the shared transport (L1) using shared motion (L3) + timing (L4).
is_exhausted() — end/empty-state detection (usually a template match).
accepts_payload — whether the target attaches content at action time (affects whether active mode does the upstream work at all).
(passive mode) wait_for_decision() — infer the human's action from region-split frame diffs (L2).
**You reuse unchanged: the timing layer (L4), the motion synthesizer (L3), the transport (L1), the rate limiter (L5), the verify_*/fail-closed pattern (L6), and the config schema.**

**You must not: add a bespoke delay scheme, hand-roll gesture jitter, read an instrumented inspection tree, install an on-target agent, or hardcode coordinates. If you're doing any of these, the reusable layer already exists — use it, or improve it in place so every target benefits.**


## 6. Portability checklist for a new target
Run this before writing a line of the new driver:

not done
**Threat model. Does the target run server-side integrity/attestation? Behavioral analytics? A named anti-automation vendor? Record findings with confidence levels. Don't guess; if unknown, mark it unknown and design conservatively.**
not done

### Layer 0. Confirm environment/network/identity posture meets the bar the threat model implies (or document why a layer is safely skippable).
not done

### Layer 1. Is a genuine input path available? If not, a lower-fidelity fallback — note the reduced authenticity. Browser target → stealth engine + real binary + no injected DOM.
not done

### Layer 2. Capture working; collect glyph/label templates for every action and modal; set change thresholds by measurement.
not done

### Layer 3/4. Reuse as-is. Re-measure only if the device's input hardware or the target's cadence differs materially from the reference.
not done

### Layer 5. Set conservative per-target caps; get the action-type ratio right first.
not done

### Layer 6. Wire verify_* for each action's expected end-state; enable the debug log.
not done
**Resolve every LIVE-VERIFY against a real session before trusting active mode.**
not done
**Passive before active. Validate in observe mode; flip to autonomous only once passive is clean.**

## 7. Parameter reference (reference calibration — recalibrate per device)
These are reference values from one real device/human; treat them as starting points and re-measure (§9) for a new environment. Changing a shared value changes every target — that's the point — so justify with a measurement.

**Parameter	Reference value	Meaning / source**
Timing σ	0.22	log-normal spread around any anchor delay
Input report rate	~180 Hz	match the measured digitizer/input rate
Fitts a, b	0.11, 0.17	Shannon movement time, touch-typical
Default target width	180 px	Fitts W for a typical control
Velocity peak / σ	0.35, 0.18	lognormal tangential-velocity profile
Tremor θ / amplitude	22.0, 2.2 px	OU mean-reversion; base jitter (speed-scaled 0.4–1.0×)
Pressure α, β	1.25, 0.85	beta ramp shape (rise→decay)
Pressure peak / floor	0.95 / 0.22	normalized; floor ≈ sensor detection threshold
Contact size peak	0.55	normalized contact-major
Press dwell median / σ	0.13 s, 0.25	lognormal, clamped 0.04–0.35 s
Press micro-slip	2.5 px	contact slide on impact
Think time (affirmative)	shift 1.2, μ 0.65, σ 0.35 → ~3.2 s	faster reaction
Think time (rejecting)	shift 1.8, μ 1.45, σ 0.42 → ~6.9 s	slower reaction
Read/consider dwell	~1.1 s	per-item consideration pause
State-change threshold	9.0	mean grayscale delta (0..255, 24×24) = "region changed"
Volume caps	~30 / session, ~50 / day	conservative starting caps
Committing-action cap	~15 / session	holds action-type ratio human (the key cap)
Between-action anchor	~3.5 s	typical inter-action pause
(Provenance for the input-derived numbers must be recorded — device, date, method — wherever you keep them. Undocumented constants rot.)


## 8. Anti-patterns (do not ship these)
❌ sleep(2) or uniform(1, 3) on an action path → use the timing layer.
❌ A high-level "inject tap/click" API as the primary transport when a genuine input path exists → it's synthetic-flagged; genuine kernel/OS input isn't.
❌ Reading an instrumented inspection/accessibility tree or installing an on-target agent → the exact footprint Layer 0 forbids, flagged even in passive mode.
❌ Fixed-coordinate actions as the primary locator → controls move; vision-match the glyph, keep the coord only as fallback.
❌ White-noise jitter or a symmetric ease on gestures → correlated tremor + asymmetric velocity are the point.
❌ Zero/constant pressure while in contact → physically impossible on a real sensor; use the beta ramp with a floor.
❌ Blind retry after a missed action → fail closed (Layer 6).
❌ High volume with a skewed action-type ratio → often the most reliable bot signal.
❌ Hardcoded coords/thresholds/caps → config, per target.
❌ Compromised environment / VPN / datacenter IP for an attestation-gated target.
❌ Autonomous action on an identity you care about → soft-bans are silent; isolated identity only.

## 9. Calibration protocol (deriving numbers for a new device)
The models are general; the constants are device-specific:

Capture real input. With a human using the target, record raw input traces for a representative set of gestures. Extract: report rate, samples/gesture, pressure min/mean/max, contact size range, dwell and reaction times.
Fit the profiles. Set the report rate to measured; pressure floor/peak from raw min/mean; press dwell from the dwell distribution; think-time params from the reaction-time distribution per decision type.
Set vision thresholds by measuring frame deltas for real transitions vs noise; pick the change threshold between them.
Collect templates at native resolution for every action glyph/label and modal.
Record provenance — date, device, method — next to the constants. Undocumented constants rot.

## 10. Improving this standard (evolving "as one")
The shared layers are the leverage point: a better model here upgrades every target at once.

**Change the shared module, not a per-target copy. If a target needs different behavior, first ask whether it belongs in the shared layer as a parameter. Bespoke per-target humanization is a smell.**
**Back every constant change with a measurement (§9) and update §7's provenance. No vibes-based tuning.**
**Keep the threat model in sync. If you add a defense, record the vector it answers and the confidence. If a vector is disproven or a trick is patched, update the standard and any affected re-check trigger.**
**Preserve testability. Any change to Layers 3–5 stays pure and rng-injectable, with offline tests.**
**Re-check triggers. Browser/engine detection changes; platform attestation policy changes; a target's actual vendor stack becoming known; measured drift in a device's input hardware. When one fires, update the standard first, then the drivers.**
This standard is prescriptive for everything built against it. When an implementation and this document disagree, that is a bug in one of them — reconcile, don't ignore.