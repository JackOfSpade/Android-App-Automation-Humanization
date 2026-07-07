# Humanization Standard — Android App Automation

**Status: normative reference (Revision 2).** Single source of truth for making automated
touch input on a physical Android phone indistinguishable from a human hand. Written to be
implemented against: anyone told to "automate Android app X humanly" reads this, adopts the
philosophy, and reuses the shared layers instead of inventing a per-app scheme.

**Framing.** This is a defensive / QA-and-research engineering standard for app-agnostic
automation on hardware you own, used for regression testing, anti-fraud red-teaming, and
behavioral-realism research. It is not an operational recipe for defeating a specific
service's anti-abuse controls. The distinction matters: several sections below exist to help
you *detect where your own automation diverges from a real human*, not to help you attack
someone else's users.

**Scope.** Fixed platform, open app set. The target is always a physical Android device
driven host-side over ADB (no on-device agent). The app is a variable — this standard is
app-agnostic and must not bake in any one app's flow. What is *not* variable: it's a real
touchscreen attached to a real handheld device, so taps and swipes carry pressure, contact
geometry, hardware cadence — **and inertial side effects on the device's own sensors.** Those
attributes are part of the fingerprint we reproduce.

**Confidence taxonomy** (put it on every claim that drives a decision):
`HIGH` = official docs / reproducible behavior; `MEDIUM` = credible research, not
app-confirmed; `LOW` = anecdote / reverse-engineering guess / speculative.

---

## What changed in Revision 2 (and why)

Revision 1 was a strong *touch-path* standard. Independent technical review converged on one
verdict: it optimizes **marginal** realism (each of path, tremor, pressure, timing is locally
plausible) while modern defenses exploit **joint** realism (touch, inertial motion, contact
geometry, device metadata, and session history are correlated projections of one physical
event — a hand holding and touching a phone). A perfect Bézier curve is worthless next to a
flat accelerometer trace during the tap that drew it.

The six highest-leverage changes, each carried through the layers below:

1. **Model the human, not the gesture.** Observable actions now emerge from a persistent
   latent state (goal, attention, confidence, fatigue, familiarity) plus motor control —
   not from independent per-action random draws. (New master principle; see §1, §2, L5.)
2. **Cross-channel coherence is a first-class layer.** Every touch must produce coherent
   inertial/orientation side effects on the device's own IMU. Flat motion during a "human"
   tap is the single most evidence-backed tell. (New in L4; `HIGH`.)
3. **The virtual digitizer is session infrastructure, not a per-gesture object.** Rev 1's
   register→report→destroy-per-gesture pattern is observable device churn via
   `InputManager.InputDeviceListener`. Real touchscreens never appear and disappear. (Fix in
   L1; `HIGH`.)
4. **Constants are calibrated priors, not universal truths.** The report rate, Fitts terms,
   tremor, pressure shape, and timing σ vary 1–10× across devices/tasks/users. Calibration
   (§10) is now a **precondition for production**, not an optional appendix. (§8; `HIGH`.)
5. **Better motor structure.** Vanilla Fitts + smooth-curve + independent tremor is replaced
   by FFitts target acquisition and minimum-jerk submovements with corrective endpoints —
   the right *shape* of variability, concentrated near the target. (L3; `MEDIUM`.)
6. **Scope honestly at the edges.** Multi-touch/two-thumb input, Android scroll-fling
   physics, observe-mode replay diversity, and network/SDK telemetry are named as in-scope
   gaps (L3, L5) or an explicit boundary layer (L7) rather than silently omitted.

---

## 1. Philosophy — the prime directives

Everything follows from these. When a case isn't covered, derive from them.

**Master principle — model the human, not the gesture.** Every observable action (a tap, a
swipe, a pause, an abandon) should emerge from latent cognitive state — goal, attention,
confidence, memory, fatigue, familiarity — together with motor control, rather than from
independently randomized parameters. A human notices something, inspects it, becomes
convinced, sometimes hesitates, sometimes changes their mind, sometimes ignores it. Movement
is only the final stage. This single principle unifies most of what follows. (`MEDIUM`.)

**Preserve covariance across channels.** Human data are not independent draws from Fitts,
Ornstein–Uhlenbeck, a beta pressure ramp, and a log-normal timer. They are correlated
projections of one latent hand-phone-mind state. The improvement is never "add more
randomness"; it is "make the channels co-vary." Detectors increasingly score *joint*
consistency: does the inertial micro-motion match the tap, does the input-device metadata
match the built-in panel, does the pause match the task. Optimize the joint distribution, not
the marginals. (`HIGH` that fusion is used; specific weights `LOW`.)

**The device is the weak link, not the evasion.** No pressure curve saves a rooted phone, an
emulator, a datacenter IP, or an on-device automation helper. Get Layer 0 right first; it
dominates every touch trick. (`HIGH`.)

**Reduce footprint before you fake signals.** The best synthetic touch is one that doesn't
need to lie because it flows through the real kernel input pipeline. Prefer a genuine input
path (a persistent virtual HID digitizer) and observation without instrumentation (screencap
+ vision, not the accessibility tree) over injecting artifacts and hiding them.

**Model the hand's motor control, don't randomize the machine.** A human finger obeys motor
control — target-acquisition laws, asymmetric velocity, correlated tremor, corrective
submovements, a pressure ramp, log-normal timing. Draw from the model that generated real
`getevent` data, calibrated to measurements. `uniform(a, b)` is itself a tell; constant
pressure is a louder one; a flat IMU during the tap is the loudest.

**Behavior is a distribution, not a tap.** Detection weights aggregates — action rate, the
committing-action ratio, session length, inter-action cadence, cross-session trajectory
diversity — more than any single gesture. A perfectly humanized tap is worthless if the rate,
ratio, or repetition is robotic. Cap and shape the aggregates (Layer 5).

**Calibrate, don't hardcode.** Every numeric constant in this document is a *reference prior*
measured on one phone with one human. It is a starting point, not a universal truth. A shared
constant changes every app, so back every change with a measurement (§10). Numeric precision
without provenance is false confidence.

**Fail closed, never flail.** A missed tap followed by blind retries is exactly the erratic
burst detection loves. On any unexpected screen — or any cross-channel incoherence — stop and
preserve evidence (Layer 6).

**Passive ≪ Active, but passive is not free.** Observe mode (the human taps, we only read the
screen) removes almost all *generative* behavioral evidence. Autonomous tapping is where the
risk lives; default to observe, treat auto as the deliberate, gated exception. But recorded
sessions replayed verbatim are their own tell — genuine humans never reproduce identical
motor traces — so observe/replay carries a non-repetition obligation (L5). (`MEDIUM`.)

**Corollary — determinism where it doesn't cost realism.** Every motion/timing/state
primitive takes an injectable RNG (`rng=Random(seed)`) so behavior is unit-testable and
reproducible, defaulting to real randomness in production.

---

## 2. The coupled system we model (why Android ≠ click-automation)

We do not model "a pointer that moves nicely." We model a **latent hand-phone-mind state**
and emit every channel it would project. A physical Android touchscreen reports, and
`MotionEvent` exposes to any app, far more than `(x, y)` — and the device around it exposes
still more.

**Touch-stream attributes** (per-sample, both taps and swipes):

| Attribute | `MotionEvent` / kernel source | What synthetic input gets wrong |
|---|---|---|
| Pressure | `getPressure()` / `ABS_MT_PRESSURE` | constant or ~0; a real finger ramps up, plateaus, decays |
| Contact size | `getSize()` / `ABS_MT_TOUCH_MAJOR` | absent; a real contact has finite, varying, evolving pad area |
| Contact geometry | touch/tool major-minor, orientation | a fixed circle; real pads roll and deform with direction/angle |
| Tool type | `getToolType()` → `TOOL_TYPE_FINGER` | injection paths can look wrong / flagged |
| Report cadence | VSYNC-batched digitizer (device-specific) | injected events arrive at the wrong rate/timing |
| Motion path | per-sample history in the `MotionEvent` | a straight, evenly-spaced, jitter-free line |
| Historical samples | `getHistoricalX/Y/EventTime` batched in `ACTION_MOVE` | a plausible endpoint with no plausible in-between structure |
| Pointer identity | stable IDs across `ACTION_POINTER_DOWN/UP` | a single teleported point; no multi-touch lifecycle |
| Multi-touch | `getPointerCount()` / slots | one idealized finger; no two-thumb, pinch, or incidental contact |

**Device-and-sensor attributes** (outside the touchscreen, correlated with it):

| Attribute | Source | Why it matters |
|---|---|---|
| Inertial micro-motion | accelerometer / gyroscope | a handheld tap transfers a mechanical impulse; a bench phone is flat (`HIGH`) |
| Orientation / grip | rotation vector, gravity | grip and hold posture bias every reach; a static gravity vector is anomalous |
| Input-device identity | `InputDevice` (source, ranges, VID/PID, `isExternal`/`isVirtual`, descriptor) | a virtual panel with wrong ranges or an external/virtual flag betrays injection (`HIGH`) |
| Device lifecycle | `InputManager.InputDeviceListener` add/remove | a digitizer that appears/disappears per gesture is impossible for a built-in panel (`HIGH`) |

The consequence: the goal on Android is **not** "move the pointer nicely." It is to emit a
per-sample touch stream `(t, x, y, pressure, size, major/minor, orientation, tip, pointer_id)`
that reproduces all of the above **and** to emit coherent inertial/orientation side effects on
the device's own sensors, delivered through a persistent input path whose metadata matches the
built-in panel. That is Layers 1, 3, and 4, and it's why Android humanization is deeper than
desktop/web click automation. (Whether a given app reads a given channel is `MEDIUM`; that a
real held device produces all of them is `HIGH` — so we reproduce them regardless.)

---

## 3. The layered model

```
Latent state    Goal · Attention · Confidence · Fatigue · Familiarity · Memory
(cross-cutting) └─ drives every layer below; see L5 ──────────────────────────┐
                                                                              │
Layer 7  Network & SDK telemetry     TLS/JA4, request timing, attestation  (boundary)
Layer 6  Verification & fail-closed  "did the screen change AND cohere? else HALT"
Layer 5  Behavioral & cognitive state HumanState, journey grammar, non-repetition, caps
Layer 4  Timing & sensorimotor sync   stateful think time + coherent IMU/orientation
Layer 3  Motor synthesis             FFitts + submovements + contact-patch + multi-touch
Layer 2  Perception w/o footprint    screencap + vision (NO accessibility tree)
Layer 1  Transport authenticity      persistent virtual HID digitizer, panel-matched metadata
Layer 0  Device, identity & attestation  physical stock phone, residential IP, isolated account
─────────────────────────────────────────────────────────────────────────────
         ↑ higher layers are worthless if a lower layer is compromised ↑
```

Layers 3–5 are pure, app-independent modules reused verbatim for every app. A new app supplies
only its perception (Layer 2) and action-location glue; it inherits the rest. That reuse is
what lets the standard improve "as one." Layer 4's sensorimotor coupling and Layer 5's latent
state are also shared — they are not per-app.

---

## 4. The layers in detail

### Layer 0 — Device, identity & attestation (foundation)

Owns nothing in code; gates everything.

- **Physical, stock, unrooted, Play-certified phone.** Passes Play Integrity
  `MEETS_DEVICE_INTEGRITY` (and `MEETS_STRONG_INTEGRITY` with a recent security patch on
  Android 13+); an emulator/AVD cannot — no hardware root-of-trust. No root, no bootloader
  unlock, no custom ROM. (`HIGH`.)
- **Scope Play Integrity correctly — it attests the environment, not the input.**
  `MEETS_DEVICE_INTEGRITY` / `MEETS_STRONG_INTEGRITY` say the app runs on a genuine certified
  device; `appAccessRiskVerdict` (`KNOWN_CONTROLLING` / `UNKNOWN_CONTROLLING`) flags apps that
  can capture the screen, draw overlays, or control the device. **None of these attest that a
  given `MotionEvent` came from a human finger.** A clean device verdict can coexist with a
  virtual HID source; conversely a strong verdict does not launder robotic behavior. Treat
  Play Integrity as a gating device-trust signal and model input authenticity separately.
  (`HIGH`.)
- **Model attestation-volume risk.** Google's "recent device activity" can flag devices
  requesting large numbers of integrity tokens — a real device used to automate attacks
  elsewhere still looks anomalous. Rev 1's behavioral caps counted app actions; add
  device-level token/attestation volume to the budget. (`HIGH`.)
- **No on-device automation footprint.** Do not install `uiautomator2` / `atx-agent` / Appium
  helper APKs, and do not enable an accessibility service for automation. They trip
  `appAccessRiskVerdict` (`UNKNOWN_CONTROLLING`) even in read-only observe mode, and apps can
  enumerate accessibility services via `getEnabledAccessibilityServiceList`. Drive host-side
  only. (Google API `HIGH`; app-consumes-it `MEDIUM`.)
- **Residential network, no VPN/proxy/datacenter,** for install, signup, verification, and
  every session; keep locale/timezone/geo coherent with the IP. Route natively so the
  device's own TCP/IP stack terminates connections — host-side proxies and modified HTTP
  clients alter the transport fingerprint (see L7). (`HIGH` that datacenter/VPN is penalized;
  scoring `LOW`.)
- **Identity isolation.** An account separated from anything you value, with a real (non-VoIP)
  number — soft-bans/shadow-throttling are silent and unconfirmable, and bans can federate
  across a provider's apps via device/photo/face/phone/payment hashes. Autonomous use is only
  sane on a disposable identity. (`HIGH` for federation where documented.)
- **Portability note:** if a target app runs no server-side integrity/behavioral checks,
  Layer 0 relaxes — but confirm which gates apply (§7) before assuming you can skip it. Don't
  guess.

### Layer 1 — Transport authenticity (persistent, pressure-carrying, panel-matched)

"Reduce footprint before you fake signals" in code: deliver touches through the real kernel
input pipeline, carrying the full contact envelope, so there's no injection artifact to hide.

- **Preferred: a non-root virtual HID touchscreen.** Create a virtual multitouch digitizer
  through the stock `/system/bin/hid` tool over `/dev/uhid` (writable by the unprivileged
  shell domain — no root, no installed helper). Events flow through the genuine kernel input
  pipeline: `TOOL_TYPE_FINGER`, variable pressure, VSYNC-batched, not injection-flagged.
  Strictly better than `adb shell input tap/swipe`, which is a synthetic injection with no
  pressure.
- **The device is session-scoped, not per-gesture. (Rev 2 fix, load-bearing.)** Rev 1's
  register → enumerate → report → **destroy per gesture** is a fingerprint: UHID destruction
  is a *disconnect*, and any app can subscribe to `InputManager.InputDeviceListener` to see
  input-device add/remove churn at gesture cadence — something a built-in panel never does.
  Register **one** persistent digitizer for the session and stream all gestures through it;
  destroy it only at session teardown. If SELinux denies a held-open FIFO to the shell domain,
  solve the plumbing (a resident host-side writer, a named pipe held by an allowed context)
  rather than papering over it with re-enumeration. Per-gesture enumeration is now an
  anti-pattern (§9). (`HIGH`.)
- **The descriptor must carry the full contact envelope.** Single-finger-**capable**
  multitouch digitizer with Tip Switch / Confidence / Contact ID / X / Y / Tip Pressure
  (0..255) / Touch-Major / Touch-Minor / Orientation / Contact Count. Build X/Y logical
  maxima from the live screen size so device coordinates map 1:1 to pixels on any resolution.
  Omit the Contact-Count-Maximum feature report — it triggers a kernel `GET_FEATURE` the HID
  stream can't answer and kills the device mid-enumeration.
- **Panel-matched input-device identity.** A digitizer that is geometrically human-like can
  still betray itself through `InputDevice` metadata. The virtual device should report
  `SOURCE_TOUCHSCREEN` / `SOURCE_CLASS_POINTER`, classify as internal (not external / not
  virtual where observable), expose pressure/size/major-minor **motion ranges consistent with
  the host's real panel**, and return a stable descriptor across restarts. A `vendor_id`/
  `product_id` of `0x0000` with a generic name (`uhid-touchscreen`) is a giveaway; sane,
  panel-plausible identifiers are the floor. (`HIGH` that the metadata is queryable; that a
  given app queries it is `MEDIUM` — reproduce it regardless.) *Note: cloning identifiers of a
  specific OEM panel is a device-authenticity measure for hardware you own and test on; it is
  not a licence to impersonate someone else's device to a service.*
- **Match Android's event structure, not just endpoints.** `ACTION_MOVE` batches multiple
  samples with historical coordinates/timestamps. Emit a report stream that produces plausible
  *current + historical* sample structure at the device's real cadence, not a sparse path that
  yields one clean coordinate per event.
- **Graceful, explicit degradation.** If `/system/bin/hid` is absent, raise a distinct "UHID
  unavailable" and fall back to the `adb input` transport — still functional, but
  pressure/size/geometry are lost; record that fidelity dropped. A `touch_backend:
  auto|uhid|adb` config knob forces the choice.
- **Text entry** goes through ADB (`input text` / clipboard-paste), not simulated per-key
  taps, **unless** the app reads key timing or the flow is text-heavy (login, search, chat,
  OTP, checkout) — in which case keystroke dynamics become a channel of their own (see L3/L5
  IME note). (`MEDIUM`.)

### Layer 2 — Perception without footprint

Reading the accessibility tree or running an on-device inspector is the footprint Layer 0
forbids. Instead:

- **Capture, don't inspect.** `adb exec-out screencap` frames only. Dedupe consecutive frames
  by a downsampled signature (e.g. 24×24 grayscale) to tell "the screen advanced" from "frame
  noise" with no UI hierarchy. A repeated signature = the screen stopped changing.
- **Locate actions by vision, not fixed coordinates.** Template-match the glyph/label with
  normalized cross-correlation + non-max suppression, filtered by screen region. Controls move
  (banners, dynamic layouts, per-item heights) and can blend into their background — a fixed
  screen-fraction is unreliable. Keep a calibrated fixed-fraction fallback for when vision
  misses.
- **Region-split diffing distinguishes kinds of change:** a bottom sheet sliding up (bottom
  changes, top stays) vs a full transition (top changes too). This is how observe mode infers
  the human's tap-vs-scroll-vs-transition from pixels alone.
- **Model perceptual fallibility. (Rev 2.)** A vision loop that instantly and always locates
  the target, then acts, is *too competent* at the perception→action boundary. Real users miss
  visual changes, hesitate after animations, overshoot scroll targets, misread disabled
  states, and re-check high-stakes screens. Confidence from template-match quality should feed
  the latent state (L5): a weak match means inspect/hover/hesitate, not instant commit.
  (`MEDIUM`.)
- **Degrade safely, never silently.** If frames won't decode or the device wedges
  (empty/truncated screencaps), refuse to run rather than continue blind — a blind run
  mislabels manual scrolls and corrupts any data you're collecting.

### Layer 3 — Motor synthesis (taps, swipes, scrolls, with contact geometry)

The master principle at the motor level. A pure, transport-agnostic synthesizer emits the
per-sample stream Layer 1 turns into HID reports. Calibrate to real `getevent -lt` traces off
a genuine human on the reference phone. No device access, fully unit-testable, every function
takes `rng`.

**Target acquisition — FFitts, not vanilla Fitts. (Rev 2.)** Conventional Fitts's law
under-models finger-touch target acquisition because it ignores finger-contact ambiguity.
Google's FFitts variant (Bi & Zhai) explains substantially more variance (R² ≥ 0.91) by adding
an absolute finger-precision term. Use FFitts for movement time and endpoint spread; treat the
`a`/`b` terms and the precision term as **calibrated per device/user**, not fixed. (`MEDIUM`.)

**Path & tremor — submovements, not smooth-curve-plus-noise. (Rev 2.)** Human reaches
decompose into discrete minimum-jerk **submovements** with corrective adjustments that grow as
target difficulty rises — a fundamentally different *shape* of variability than a smooth Bézier
plus independent OU tremor. Generate a primary minimum-jerk ballistic phase, then 0–N smaller
corrective submovements concentrated near the target (more, and larger, for small/ambiguous
targets). Retain speed-scaled correlated tremor (OU) as a secondary texture on top, not as the
primary source of path variability. Endpoints remain exact; only the transit is noisy.
(`MEDIUM`.)

**Contact-patch evolution — not just a pressure scalar. (Rev 2.)** Model the finger pad, not a
point:

| Channel | Model | Replaces |
|---|---|---|
| Pressure | Beta ramp `uᵅ(1−u)ᵝ` (rise→plateau→decay) with a nonzero in-contact floor | constant / zero pressure |
| Size / major-minor | co-evolves with pressure; grows on press, shrinks on release | absent or constant |
| Orientation | rotates toward the direction of travel on swipes; biased by grip/handedness | fixed |
| Centroid micro-slip | damped settle-and-slide from impact as the pad compresses | a stationary point |

A capacitive digitizer only reports contact above a detection threshold — an in-contact frame
is never exactly 0; only the explicit release is. **Respect the device's pressure semantics:**
Android pressure may be a real intensity, an amplitude proxy for contact size, or simply `1.0`
when the panel doesn't measure it. A fancy beta ramp on a device that reports binary pressure
is *less* realistic than a faithful flat signal. Calibrate to what the panel actually reports.
(`MEDIUM`.)

**Tap dwell** is a lognormal down→up (reference median ~130 ms), clamped — real press dwell is
right-skewed, not a fixed press duration.

**Scrolling is a first-class behavior, governed by Android's own fling physics. (Rev 2.)** A
scroll is not an arbitrary Bézier drag. Android's `OverScroller`/`VelocityTracker` model a
spline-based fling with a fixed deceleration profile; an app can compare an injected swipe's
post-release velocity and deceleration against what its own physics would produce. Generate the
release velocity and let the *content* decelerate on the app's terms; model kinetic scroll,
content-dependent reading pauses, short corrective scrolls, overscroll/edge affordances
(rubber-band, pull-to-refresh mis-triggers), and reading-time coupling. (`MEDIUM`.)

**Multi-touch and incidental contact — the single-finger blind spot. (Rev 2.)** Real phone use
includes two-thumb typing, pinch/zoom, multi-finger scroll, resting-thumb artifacts, and
occasional palm/edge contacts, each with a proper pointer-ID lifecycle
(`ACTION_POINTER_DOWN/UP`). Model these *where the app normally elicits them* — do not sprinkle
random extra touches, because their frequency and shape depend on grip, device size, layout,
and one- vs two-handed use. Grip/handedness/thumb-reach constraints should make paths globally
plausible for the declared hold posture, not just locally smooth. (`MEDIUM`.)

**Rule for extending:** any new gesture (long-press, fling, pinch) derives its parameters from
measured `getevent` data, stays pure + `rng`-injectable, and records its calibration source in
§8. No hand-tuned constants without a measurement.

> On full musculoskeletal / physics-engine simulation: a forward biomechanical model (joint
> torques, muscle activation, minimum-jerk-plus-effort optimization) would in principle
> *generate* asymmetric velocity, submovements, and settling as physical consequences rather
> than as fitted heuristics. This is a legitimate research direction but is **not mandated
> here** — it is heavy, hard to calibrate, and the submovement/FFitts/contact-patch models
> above capture the observable structure that detectors actually score at far lower cost.
> Treat physics-based synthesis as an optional upgrade to validate against, not a requirement.
> (`LOW`/`MEDIUM`.)

### Layer 4 — Timing & sensorimotor coherence

Two responsibilities: *when* actions happen, and *what the device's sensors do* while they
happen.

**Timing** — every wait is an anchor delay × a log-normal multiplier
(`seconds · exp(N(0,σ)·σ)`, reference σ ≈ 0.22), not a uniform range — an organic long tail
(usually near the anchor, occasionally much longer, never negative). Two variants:
`human_delay(seconds)` (may be shorter or longer; ordinary pauses) and
`human_cooldown(seconds)` (never below the anchor; minimum waits and backoffs).

Per-decision **think time** is a distinct, higher-level model: a shifted-lognormal whose
parameters differ by decision type (a committing action is often a faster reaction than a
rejecting one). But a single σ, or one anchor per decision type, is **not enough** — think time
must be **stateful** (see L5): it varies with visual complexity, novelty, account age, task
risk, text length, error recovery, animation/network latency, and whether the next action is
exploratory or committing. A flat model can look human in a marginal histogram while failing
conditional checks like "time from price display to purchase," "time after OTP autofill," or
"time after a failed validation." Reaction-time distributions are skewed (ex-Gaussian /
log-logistic families); the shape is per-task, per-user — calibrate it. (`MEDIUM`.)

**Sensorimotor coherence — the highest-leverage Rev 2 addition. (`HIGH`.)** A human tapping a
handheld phone transfers a mechanical impulse to the chassis: taps produce a localized
acceleration spike, swipes produce a small rotational torque, and grip/posture produce
continuous low-amplitude micro-motion and a non-flat gravity vector. A bench-mounted,
ADB-driven phone shows anomalously flat accelerometer/gyroscope data during "human" touches —
and fusing one motion channel with touch roughly halves bot-detection error in published work,
which is why commercial behavioral-biometrics products advertise touch+IMU fusion as core.

For every synthesized touch, Layer 4 must produce a coherent inertial/orientation side effect,
temporally and spatially aligned to the touch (tap location → impulse direction; swipe
direction → torque axis). Two implementation paths, chosen by threat model and posture:

- **Handheld by a consenting tester / physical actuation.** The most faithful option: the
  phone is actually held, or mounted on a rig that induces microscopic impulses/tilts in sync
  with each gesture. No sensor mocking, so nothing to detect at the sensor API. (`MEDIUM`.)
- **Programmatic sensor injection.** Compute the predicted triaxial acceleration and angular
  velocity from touch location, contact velocity, and grip tension, and feed the sensor
  subsystem. **Caution:** sensor mocking typically needs elevated/developer privileges and can
  itself trip integrity gates — evaluate against Layer 0 before relying on it. (`MEDIUM`.)

Either way, the coherence is a **generation** requirement (produce the coupled signal) *and* a
**validation** requirement (L6 fails closed if touch and motion don't cohere). Declare the test
posture (desk-mounted vs handheld) explicitly; a desk-mounted run must not claim handheld
realism.

**Rule:** no bare `sleep(constant)` and no uniform delay on any app-facing action path — route
it through the timing layer. Short internal poll cadences the app never sees (a screenshot
loop) are exempt.

### Layer 5 — Behavioral & cognitive state

Rev 1's "behavioral hygiene" was caps. Rev 2 makes this the home of the **latent state** that
drives every other layer. Applies to auto mode; observe mode is never *capped*, but carries the
non-repetition obligation below.

**HumanState — the latent spine.** Maintain a persistent per-session state that biases every
downstream distribution, producing correlated behavior instead of independent randomness:

```
HumanState
  attention     high → fast reactions, small tremor, direct paths
  confidence    from perception match quality (L2) → inspect / hover / commit / abandon
  urgency       compresses think time and dwell
  fatigue       accumulates over the session → longer pauses, larger variance, more corrections
  familiarity   grows with repetition → think time drops, paths straighten, overshoot shrinks
  memory        visited regions, last action, last failed target, recent visual context
```

- **Confidence gates action.** High confidence → immediate movement; medium → inspect first;
  low → hover, inspect, sometimes abandon. Confidence should influence think time, swipe
  speed, hesitation, corrective motion, and cancellation probability. (`MEDIUM`.)
- **Memory suppresses redundancy.** "I already looked here" → don't re-inspect; a recently
  failed target raises caution. Memory influences eye/scan behavior, reaction time, and
  movement planning.
- **Inertia across actions.** Consecutive gestures drift rather than resetting — a fast swipe
  is followed by a slightly faster one, then a pause, then slow again. Behavior should
  autocorrelate over time.
- **Adaptation within a session.** Repetition increases familiarity: think time decreases,
  paths become straighter, overshoot drops. Behavior evolves; it is not stationary.
- **One evidence-based correction before failure.** Humans rarely blind-retry; they do one
  visually-confirmed corrective action (a slightly adjusted second tap) before stopping. This
  is distinct from blind retry (still forbidden — L6): it is a single, evidence-driven
  adjustment, then a clean stop.

**Journey grammar, not just a ratio.** The committing-action ratio cap remains the
load-bearing hygiene control — whatever tap the app treats as a conversion (like, follow,
submit, purchase) is what a bot over-produces, and an anomalous ratio is often a stronger
signal than raw volume, so cap it below total actions. But real sessions have structure a flat
ratio misses: browsing before checkout, review before transfer, reading before reply,
app-switching around OTP, hesitation-then-cancel, error-recovery slowdowns, and "negative
behavior" (abandonment, notification-shade pulls, accidental off-target taps). Define a
per-vertical journey grammar and include these. (`MEDIUM`; thresholds `LOW` — stay
conservative.)

**Non-repetition & distributional diversity — the observe/replay safeguard. (Rev 2.)** Replay
of a recorded human session, or repeated auto runs, must not reuse identical trajectories,
inter-event timings, or navigation rhythms. Behavioral-biometric systems expect stable
*distributions* but never identical *traces*; near-duplicate repetition is more suspicious than
a well-varied synthetic trajectory. Add a near-duplicate check across runs and keep behavior
inside a plausible user-specific envelope rather than on a single recorded point. (`MEDIUM`.)

**Volume, session, and account-graph caps.** Per-session and per-day volume caps; human-plausible
session windows (let L4 spread actions — don't burst); and longitudinal ceilings/cooldowns that
account for device/account/network reuse, since account-graph signals can dominate raw volume.
When a cap is hit, **stop the run** — don't substitute a different action to keep going; that
both looks robotic and corrupts any labels/data. Checks run before each autonomous action; new
apps reuse the same limiter, only the numbers move.

### Layer 6 — Verification & fail-closed

After every autonomous action the screen must change (a new item, a confirmation sheet) **and
the channels must cohere.** If not — even after a short settle — the tap missed, the app is in
an unknown state, or the automation is leaking → raise and HALT, preserving evidence, not retry
blindly.

- **Generic progress check:** the screen advanced (screencap diff over threshold).
- **Semantic end-state check:** the specific expected result (a confirmation sheet and any
  upsell/intercept modal are gone; the deck moved off the pre-tap item). A bare change-check is
  spoofable by an unrelated animation.
- **Coherence gates (Rev 2).** Fail closed not only on "UI didn't change" but on cross-channel
  incoherence: touch that produced flat IMU during a declared-handheld run; input-device
  churn / metadata drift; a trajectory that near-duplicates a prior run; a perception→action
  loop that was implausibly fast/certain for the context. These are the same self-checks used
  to find where your automation diverges from a human. (`MEDIUM`.)
- **Human-plausible verification.** A real user doesn't instantly perceive success from pixels;
  post-action dwell varies with the semantic risk of the screen. Verification itself should
  carry human-like perceptual uncertainty and dwell, not fire in zero time.
- **Distinguish a clean stop from an unexpected halt.** Clean stop (`DriverClosed` — USB/ADB
  dropped, human closed the app) → flush buffered work, restart-safe. Unexpected halt (stuck
  screen, missed tap, unknown modal, incoherence) → stop, snapshot, keep logs. Never let the
  second masquerade as the first.
- **Silent debug log** (per-run action journal + before/after screencaps and sensor snippets on
  any anomaly) makes every halt reconstructable offline at ~no runtime cost.

### Layer 7 — Network & SDK telemetry (boundary layer)

**Scope declaration, not a full spec.** This standard is a touch/UI humanization standard; the
network is largely outside its control. But three independent research passes each found that
real bot defenses (DataDome, AWS Bot Control, Cloudflare, Arkose, Kasada) fingerprint the
network/SDK layer *independent of UI behavior* — so pretending it doesn't exist is a scope bug.
What you must at least be aware of:

- **Transport fingerprinting (JA3/JA4).** TLS Client Hello characteristics identify the
  client stack. Host-side proxies, middleboxes, or modified HTTP clients yield a signature
  unlike a genuine Android app's native OkHttp/Cronet handshake. Keep all app and maintenance
  traffic on the **device's native network stack** (Layer 0), not a host-proxied path.
  (`HIGH` that JA4 is used; specific matching `MEDIUM`.)
- **Request-timing coherence.** Even with plausible UI timing, the app's *network* requests may
  show lower jitter, different batching, or hesitation that doesn't correlate with the API
  calls a real user's hesitation would produce. Perfect UI timing next to robotic request
  timing is an incoherence.
- **SDK attestation.** Some defenses verify SDK token acquisition to confirm requests come from
  a genuine app instance. This is an environment property (Layer 0/1 adjacent), not something
  the touch layer fixes.

For authorized evaluation, extend Layer 6's "did it cohere" from screen diffs toward **telemetry
diffs**: UI event stream, app-lifecycle events, request timing, and connection metadata,
checked against real-user baselines. The objective is to find where automation diverges before
trusting it — not to hand-tune a network evasion. Aggressive transport-layer tactics (dynamic
wireless-debugging pairing to mask USB state, temporal ADB disconnection during sensitive
transitions, TLS-signature matching) exist in the wild and are noted here for completeness, but
they are `LOW`-confidence, operationally fragile, and out of this standard's core scope; do not
treat them as endorsed defaults.

---

## 5. Cross-cutting principles

- **Config over constants.** No hardcoded ADB paths, screen-fraction coordinates, thresholds,
  or caps in code — everything in config, overridable per app. Code ships calibrated defaults;
  live values are verified on-device.
- **Calibration is a precondition, not an appendix.** The §8 table is reference priors. Running
  in production against real detection without completing §10 for the actual phone is
  unsupported. (`HIGH`.)
- **Purity + injectable RNG = testability.** Layers 3–5 (including HumanState) are pure, no
  I/O, seedable; unit-tested offline. Only transport (L1), perception (L2), and sensor
  coupling (L4) need real hardware.
- **Preserve covariance.** When adding any channel, wire it to the latent state so it co-varies
  with the others. An independently-random new channel makes the joint distribution *worse*,
  not better.
- **Screencap, not accessibility; vision, not hierarchy.** Restated because it's the
  most-violated rule under time pressure.
- **Detection tricks are fragile.** Integrity policy tightens; on-device signals change. Prefer
  structural choices (real phone, genuine persistent input path, coherent sensors, no helper)
  over clever ones; re-verify before relying on any single trick (§9).
- **Mark unverified values in code.** Where a screen-fraction/threshold/constant is best-effort,
  flag it inline (`LIVE-VERIFY`). Those markers are a calibration to-do list — resolve them
  against a real session before trusting auto mode.

---

## 6. Implementation contract — adding a new app

Keep the driver interface small so the orchestrator stays app-agnostic and all layers are
inherited. For app X you write only what's app-specific.

**You must provide:**

- `open_session()` — launch/attach and reach the actionable screen.
- `capture_state()` — Layer 2: perceive via screencap + vision. No accessibility tree.
- `act_primary(payload?, item_index?)` / `act_secondary()` — vision-locate the action (L2),
  then tap/swipe through the shared persistent HID transport (L1) using shared motor synthesis
  (L3), timing + sensor coherence (L4), and the current HumanState (L5).
- `is_exhausted()` — empty/end-state detection (usually a template match).
- `accepts_payload` — whether the app attaches text at action time (gates upstream work).
- `journey_grammar` — the per-vertical action structure and committing-action definition (L5).
- (observe mode) `wait_for_decision()` — infer the human's tap/scroll/transition from
  region-split frame diffs (L2).

**You reuse unchanged:** the timing + sensorimotor layer (L4), the motor synthesizer (L3), the
persistent UHID/ADB transport (L1), the HumanState + limiter (L5), the verify/coherence/fail-closed
pattern (L6), and the config schema.

**You must not:** add a bespoke delay scheme, hand-roll gesture jitter, drop pressure/geometry
to a constant, re-enumerate the HID device per gesture, read the accessibility tree, install an
on-device helper, replay a recorded trace verbatim, or hardcode coordinates. If you're doing
any of these, the reusable layer already exists — use it, or improve it in place so every app
benefits.

---

## 7. Portability checklist for a new app

- [ ] **Threat model.** Does the app run Play Integrity (which verdicts)? Behavioral analytics?
  A named anti-bot SDK? Does it read `MotionEvent` pressure/size/geometry? Does it fuse IMU?
  Does it fingerprint the network (JA4)? Record each with a confidence level; mark unknowns and
  design conservatively.
- [ ] **Layer 0.** Device/network/identity posture meets the bar the threat model implies (or
  document why a layer is skippable). Integrity verdict scoped correctly (device-trust ≠ input
  provenance).
- [ ] **Layer 1.** UHID available (`/system/bin/hid` present)? **Persistent** device registers
  and survives across gestures (verify no add/remove churn via a listener probe). Input-device
  metadata (source, ranges, internal/external) plausible against the host panel. If falling
  back to `adb input`, note that pressure/size/geometry are lost.
- [ ] **Layer 2.** `screencap` working; glyph/label templates for every action and modal;
  change thresholds set by measurement; perceptual-fallibility hooks wired to confidence.
- [ ] **Layer 3.** Motor synthesis reused as-is; re-measure only if the phone's digitizer or the
  app's cadence differs materially. Confirm scroll uses fling physics, not a raw drag, on
  scrollable surfaces; confirm multi-touch is modeled where the app elicits it.
- [ ] **Layer 4.** Declare the test posture (handheld vs desk-mounted). Sensor-coherence path
  chosen and wired; think time is stateful, not a single anchor.
- [ ] **Layer 5.** Conservative per-app caps; committing-action ratio right first;
  journey-grammar defined; non-repetition check active for observe/replay and repeated runs.
- [ ] **Layer 6.** Wire `verify_*` for each action's expected end-state; enable coherence gates
  and the debug log.
- [ ] **Layer 7.** Confirm traffic is device-native (no host proxy altering the fingerprint);
  note any SDK attestation the app performs.
- [ ] Resolve every `LIVE-VERIFY` against a real session before trusting auto mode.
- [ ] **Observe before auto.** Validate in observe mode; flip to autonomous only once observe is
  clean *and* diverse (non-repetition holds).

---

## 8. Parameter reference (reference priors — calibration is mandatory)

**These are priors measured on one reference phone with one human. They are starting points,
not universal constants — several are known to vary 1–10× across devices, tasks, and users.
Completing §10 for the actual device is a precondition for production.** Changing a shared value
changes every app — justify with a measurement and update the provenance note.

| Parameter | Reference prior | Meaning / caveat |
|---|---|---|
| Timing σ | 0.22 | log-normal spread; RT shape is skewed and per-task — recalibrate |
| Report rate | ~180 Hz **(often wrong)** | modern flagships run 240 / 720 / 1200 / 2000 Hz touch sampling; Android also *batches* `ACTION_MOVE` samples. Measure the target's real rate + batching; do not assume 180 |
| FFitts `a`, `b` | 0.11, 0.17 (+ finger-precision term) | use FFitts, not vanilla Fitts; terms are device/user-dependent — recalibrate |
| Absolute finger precision `σa` | ~1.15 mm (literature) | FFitts endpoint-ambiguity term; specify in **mm**, not px, and tie to panel density |
| Default target width | 180 px | Fitts `W` for a typical control |
| Velocity peak / σ | 0.35, 0.18 | asymmetric lognormal tangential-velocity; peak early (~35%), long decel |
| Submovement count | 0–3, ↑ with target difficulty | corrective minimum-jerk submovements near the target (Rev 2) |
| Tremor amplitude | ~2.2 px **→ specify in mm** | correlated OU texture, speed-scaled; convert to physical units per panel density |
| Pressure α, β | 1.25, 0.85 | beta ramp; **respect device pressure semantics** (may be binary / amplitude / 1.0) |
| Pressure peak / floor | 0.95 / 0.22 | normalized; floor ≈ detection threshold; never 0 while in contact |
| Contact major peak | 0.55 | normalized `ABS_MT_TOUCH_MAJOR`; co-evolves with pressure (Rev 2) |
| Contact orientation | rotates toward travel | swipe-direction/grip biased (Rev 2) |
| Tap dwell median / σ | 0.13 s, 0.25 | lognormal, clamped 0.04–0.35 s |
| Tap micro-slip | 2.5 px | finger-pad settle-and-slide on impact |
| Think time (committing) | shift 1.2, μ 0.65, σ 0.35 → ~3.2 s | faster reaction; **modulate by HumanState** (Rev 2) |
| Think time (rejecting) | shift 1.8, μ 1.45, σ 0.42 → ~6.9 s | slower reaction; **modulate by HumanState** (Rev 2) |
| Read/consider dwell | ~1.1 s | per-item consideration pause |
| Tap impulse (IMU) | ~0.3 g accel spike | coherent inertial side effect; direction from tap location (Rev 2) |
| Swipe torque (IMU) | ~1.4 °/s angular | coherent rotational side effect; axis from swipe direction (Rev 2) |
| Sensor poll rate | ~100 Hz | avoid gaps in the coherent IMU stream (Rev 2) |
| State-change threshold | 9.0 | mean grayscale delta (0..255, 24×24) = "region changed" |
| UHID lifecycle | **session-persistent** | one device per session; **not** per gesture (Rev 2) |
| Volume caps | ~30 / run, ~50 / day | conservative starting caps |
| Committing-action cap | ~15 / run | holds the committing-action ratio human (key cap) |
| Between-action anchor | ~3.5 s | typical inter-action pause; spread, don't burst |
| Non-repetition budget | near-dup < threshold across runs | reject replayed/near-identical trajectories (Rev 2) |

*(Record provenance — device, date, method — next to every constant. Undocumented constants
rot.)*

---

## 9. Anti-patterns (do not ship these)

- ❌ `sleep(2)` / `uniform(1, 3)` on an action path → use the timing layer.
- ❌ `adb shell input tap/swipe` as the primary transport → synthetic-flagged, no
  pressure/size/geometry; a persistent UHID device is genuine kernel input.
- ❌ **Registering and destroying the HID device per gesture** → observable add/remove churn via
  `InputDeviceListener`; a built-in panel never disconnects between taps. Persist it. (Rev 2.)
- ❌ **Flat IMU / static gravity vector during a "human" tap** → the strongest single tell on a
  bench-mounted phone; produce coherent inertial side effects or declare desk-mounted and fail
  closed. (Rev 2.)
- ❌ Constant or zero pressure (or a fixed contact size/orientation) while the finger is down →
  physically impossible; ramp pressure/size/orientation together, on taps and swipes.
- ❌ Reading the accessibility tree / installing `uiautomator2` / any on-device helper → the
  exact footprint Layer 0 forbids, flagged even in observe.
- ❌ Fixed-coordinate taps as the primary locator → controls move; vision-match the glyph, keep
  the coord only as fallback.
- ❌ Vanilla Fitts + smooth-curve + white-noise/OU-only tremor as the whole motor model → use
  FFitts + corrective submovements + contact-patch evolution. (Rev 2.)
- ❌ Treating a scroll as an arbitrary Bézier drag → model it against Android fling physics.
  (Rev 2.)
- ❌ Single-finger-only modeling for text-heavy or gesture-rich apps → model two-thumb, pinch,
  and incidental contact where the app elicits them. (Rev 2.)
- ❌ Replaying a recorded human session verbatim / identical trajectories across runs → humans
  never reproduce identical traces; enforce non-repetition. (Rev 2.)
- ❌ A single log-normal σ standing in for all think time → make it stateful (fatigue,
  familiarity, confidence, task risk). (Rev 2.)
- ❌ Blind retry after a missed tap → one evidence-based correction, then fail closed (L6).
- ❌ Trusting a strong Play Integrity verdict to launder robotic behavior → device-trust ≠
  input provenance. (Rev 2.)
- ❌ High volume with a skewed committing-action ratio → often the most reliable bot signal.
- ❌ Host-proxied / modified-client network traffic altering the TLS fingerprint → keep traffic
  on the device's native stack. (Rev 2.)
- ❌ Hardcoded coords/thresholds/caps, or shipping the §8 priors without §10 calibration.
- ❌ Emulator / VPN / datacenter IP / rooted phone for an integrity-gated app.
- ❌ Autonomous action on an account you care about → soft-bans are silent; isolated identity
  only.

---

## 10. Calibration protocol (deriving numbers for a new phone)

The models are general; the constants are device-specific. This is required before production,
not optional.

1. **Capture real input.** With a human using the app, record `getevent -lt` for a
   representative set of taps and swipes. Extract: report rate (Hz) **and batching structure**,
   samples/gesture, raw pressure min/mean/max (`ABS_MT_PRESSURE`), contact major/minor range
   and orientation (`ABS_MT_TOUCH_MAJOR/MINOR`), dwell and reaction times, and submovement
   structure near targets.
2. **Capture the coupled sensors (Rev 2).** Simultaneously log accelerometer/gyroscope while
   the human taps and swipes, held as the automation will run. Extract the per-tap impulse
   magnitude/direction and per-swipe torque axis/magnitude, and the resting grip micro-motion.
   These calibrate Layer 4's coherence model.
3. **Fit the profiles.** Report rate + batching → measured; pressure floor/peak → raw min/mean
   **and the panel's pressure semantics**; contact geometry → measured ranges; FFitts terms and
   `σa` → target-acquisition data (in mm); tap dwell → the dwell distribution; think-time params
   → the reaction-time distribution *per decision type*.
4. **Profile the input device.** Query `InputDevice` for the real panel's source, ranges, and
   internal/external classification; match the virtual device's metadata to it.
5. **Set vision thresholds** by measuring frame deltas for real transitions vs noise; pick the
   change threshold between them.
6. **Collect templates** at the phone's native resolution for every action glyph/label and
   modal.
7. **Validate against detectors, not intuition (Rev 2).** Run generated taps/swipes/scrolls
   through a local multimodal check (touch + IMU features, à la published BeCAPTCHA-style
   feature sets) and confirm they fall inside human envelopes *jointly*, not just per-channel.
8. **Record provenance** — date, device, method, tester — next to every constant.

---

## 11. Evolving the standard (improving "as one")

The shared layers are the leverage point: a better model here upgrades every app at once.

- **Change the shared module, not a per-app copy.** If an app needs different behavior, first
  ask whether it belongs in the shared layer as a parameter. Bespoke per-app humanization is a
  smell.
- **Back every constant change with a measurement** (§10) and update §8's provenance. No
  vibes-based tuning.
- **Add channels through the latent state.** New signals (a new sensor, a new gesture, an IME
  model) must be wired to HumanState so they co-vary. An independently-random addition degrades
  joint realism.
- **Keep the threat model in sync.** Record the vector each defense answers and its confidence;
  when a vector is disproven or a signal changes, update the standard and any affected re-check
  trigger.
- **Preserve testability.** Any change to Layers 3–5 stays pure and `rng`-injectable, with
  offline tests. Sensor-coherence and transport stay behind the same interfaces.
- **Re-check triggers.** Play Integrity policy changes (DEVICE vs STRONG, new verdicts); a
  target's anti-bot SDK becoming known; measured drift in a phone's digitizer or sampling rate;
  new evidence on whether apps read pressure/size/geometry, fuse IMU, or fingerprint the
  network; new adversarial-generation or detection literature. When one fires, update the
  standard first, then the drivers.
- **Prescriptive for everything built against it.** When an implementation and this document
  disagree, that's a bug in one of them — reconcile, don't ignore.

---

## Appendix — evidence base and honest limits

This revision is grounded in Android platform documentation (Play Integrity verdicts,
`MotionEvent`, `InputDevice`, `InputManager.InputDeviceListener`, `OverScroller`, touch-device
config, UHID kernel semantics), HCI motor-control research (FFitts, minimum-jerk submovements,
lognormal/ex-Gaussian timing), behavioral-biometrics literature (Touchalytics, HMOG,
BeCAPTCHA/BeCAPTCHA2, TapPrints, replay/mimicry studies), and the published capabilities of
commercial anti-fraud products (touch+IMU+device+network fusion).

**Honest limits.** (1) Commercial vendors do not publish full feature sets, so exact detection
weights are `LOW`-confidence throughout. (2) The `HIGH`-confidence core is structural — real
held devices produce coherent multi-channel signals; a bench-driven phone does not — not
numeric. (3) This standard makes an implementation *harder to distinguish*, on the specific
channels it models, against the detectors described; it does not license the word
"indistinguishable" without the §10 calibration and §10.7 adversarial validation actually
completed for the target. (4) Network/SDK detection (L7) is acknowledged, not solved, here.
Treat every gap named in Rev 2 as a place the previous version silently over-claimed.
