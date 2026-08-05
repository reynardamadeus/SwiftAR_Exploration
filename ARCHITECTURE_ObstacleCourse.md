# Obstacle Course Mode — Architecture & Roadmap

Educational AR robotics for ages 6–10. The child builds a **physical** obstacle
(LEGO / real objects on a table), the app scans it into **clean digital AR
obstacles**, drops in a **customizable vehicle**, simulates a run with RealityKit
physics, decides **pass/fail at a finish line**, and gives **child-friendly
engineering feedback** that suggests a concrete redesign — closing the
design-iteration loop.

This document is written **against your existing `ARTutorial` codebase**, not a
greenfield app. Most of the physics and customization machinery already exists;
the new work is a focused obstacle-course layer on top of it.

---

## 1. What already exists vs. what is new

| Capability | Status | Where |
|---|---|---|
| ARKit session + horizontal-plane raycasting | ✅ exists | `PhysicsPlaygroundCoordinator`, `EnvironmentScanCoordinator` |
| Scene-understanding reconstruction → colliders | ✅ exists | `EnvironmentScanCoordinator` |
| Impulse-driven locomotion (never scripts motion) | ✅ exists | `RobotControlSystem`, `PhysicsRobotComponent` |
| Static/dynamic physics bodies + `PhysicsSimulationComponent` gotcha | ✅ exists | `PhysicsSceneFactory` |
| Vehicle customization data (tire type, wheel scale, body L×W×H, CoG) | ✅ exists | `RobotConfig`, `RobotBuilder`, `WheelFactory` |
| **Scan a physical obstacle → footprint regions** | 🆕 new | `ObstacleScanner` |
| **Convert regions → clean AR props (rock/ramp/bridge/tunnel)** | 🆕 new | `ObstacleKind`, `ObstacleFactory` |
| **Start pad + finish line + assembled course** | 🆕 new | `CourseFactory` |
| **Run telemetry + pass/fail evaluation** | 🆕 new | `CourseRunComponent`, `CourseEvaluationSystem` |
| **Engineering feedback → suggested `RobotConfig` change** | 🆕 new | `FeedbackEngine`, `EngineeringFeedback` |
| **Config-driven physics vehicle (tires→friction, wheels→clearance)** | 🆕 new | `VehicleFactory` |

The new files live in `ARTutorial/Features/ObstacleCourse/`. Because the project
uses **XcodeGen**, adding `.swift` files under the sources folder and re-running
`xcodegen generate` is enough — no `.pbxproj` conflict.

---

## 2. Framework responsibility per task

| # | App task | Primary Apple framework | Notes |
|---|---|---|---|
| 1 | Scan physical obstacle | **ARKit** (camera frame, world tracking, plane detection) + **Vision** (footprint segmentation) | Frame pixel buffer from `ARFrame.capturedImage`; plane from ARKit |
| 2 | Detect overall shape/placement | **Vision** + **ARKit raycast** | Not per-brick; per *region*. Human-in-the-loop confirm |
| 3 | Convert to clean AR obstacles | **RealityKit** | Pre-authored props scaled to the detected footprint |
| 4 | Place customizable vehicle | **RealityKit** + your `RobotConfig` | `VehicleFactory` builds a physics body from the config |
| 5 | Simulate driving | **RealityKit physics** | Reuse `RobotControlSystem` impulse locomotion |
| 6 | Evaluate finish | **RealityKit** collision/geometry | Finish = trigger volume; `CourseEvaluationSystem` |
| 7 | Engineering feedback | Plain Swift rules | `FeedbackEngine` maps telemetry → advice |
| 8 | Redesign vehicle | **SwiftUI** + `RobotConfig` | Your existing editor; feedback pre-fills a suggestion |
| 9 | Test again | **RealityKit** | Rebuild vehicle from new config, re-run |
| — | UI / navigation | **SwiftUI** | `ObstacleCourseScreenView`, feedback sheet |

RealityKit does the heavy lifting for anything physical. Vision is used **only**
for a coarse 2D footprint mask — deliberately the smallest CV surface possible.

---

## 3. Scanning pipeline (simplest feasible, human-in-the-loop)

We do **not** try to recognize LEGO bricks. Recognizing arbitrary brick
assemblies is a production-grade CV problem and is unnecessary — the learning
goal is "there is a rock / ramp / tunnel here," not "this is a 2×4 red brick."

Pipeline stages:

1. **Detect the table.** ARKit horizontal-plane detection (already running).
   The plane is the reference surface `y = table`.
2. **Frame the obstacle.** On-screen guide rectangle asks the child to point the
   iPad down at the objects. Capture one `ARFrame`.
3. **Segment the footprint (Vision).** Run
   `VNGenerateForegroundInstanceMaskRequest` (subject lifting) — or, as an even
   cheaper fallback, `VNDetectContoursRequest` / `VNDetectRectanglesRequest` —
   against the captured image to get the 2D mask/bounds of "stuff standing on the
   flat table." This yields one or more **blobs**, not bricks.
4. **Lift blobs into world space (ARKit).** For each blob's screen-space corners,
   `arView.raycast(from:allowing:.existingPlaneGeometry, alignment:.horizontal)`
   onto the table plane. This gives a **world-space footprint** (center + extents
   on the plane) for each region.
5. **Estimate height.** Without LiDAR, height is ambiguous from one frame, so the
   MVP uses **category presets** (a rock is knee-high to the vehicle, a tunnel
   opening is ~1.2× vehicle height, etc.). *Optional enhancement:* on a LiDAR
   iPad, sample the reconstructed mesh over the footprint for a real height.
6. **Human-in-the-loop confirm.** Show the detected regions as translucent boxes
   and let the child tap each one to pick / confirm its category (rock, ramp,
   bridge, tunnel). This one tap removes ~90% of the CV risk and is pedagogically
   fine — the child is *labeling their own build*.

`ObstacleScanner` returns `[DetectedObstacle]` (world footprint + estimated
height + suggested kind). Steps 3–5 are isolated behind that one type, so you can
upgrade the detector later without touching the rest of the app.

---

## 4. Converting a region into clean AR content

Each `DetectedObstacle` maps to an `ObstacleKind` and is realized by
`ObstacleFactory` as a **pre-authored RealityKit prop scaled to the footprint**:

- **Rock** — a static blocker. Must be *driven around* or *climbed* if low enough.
- **Ramp** — a tilted static box (same trick as `PhysicsSceneFactory`'s ramp) the
  vehicle climbs via friction + normal force.
- **Bridge** — a raised static deck with a gap underneath; teaches clearance/path.
- **Tunnel** — an arch/portal with a fixed opening height; teaches vehicle height.

Every prop is a `ModelEntity` with matching **visual mesh + collision shape** and
a `.static` `PhysicsBodyComponent` — identical to how your `makeStaticBox` already
works, so it drops straight into the same simulation. Props carry an
`ObstacleMarkerComponent(kind:)` so the evaluation + feedback systems can reason
about *what* the vehicle touched.

Using a small prop library instead of reconstructing exact geometry is the single
biggest MVP simplification, and it also makes the digital world look clean and
"game-like" for kids rather than a noisy mesh of their LEGO.

---

## 5. RealityKit physics configuration

Follow the exact pattern your `PhysicsSceneFactory` already establishes:

- **One physics body type:** `PhysicsBodyComponent(mode:)` switched between
  `.static` (table, rocks, ramp, bridge, tunnel, finish deck) and `.dynamic`
  (the vehicle).
- **Simulation host:** put a `PhysicsSimulationComponent` on the **anchor**
  (parent of all bodies), never on a body — same gotcha you already documented.
- **Vehicle body:** a single `.dynamic` box (`HasPhysicsBody, HasPhysicsMotion`)
  built by `VehicleFactory` from the `RobotConfig`:
  - **Tire type → friction material.** RealityKit has no wheel-collider/drivetrain
    like Unity, so the tire choice sets the body's `PhysicsMaterialResource`
    friction: `smooth` ≈ 0.45 (slippery/racing), `offroad` ≈ 0.95 (grippy),
    `heavy` ≈ 0.8. (Adding a `snow` case is a one-line enum addition to your
    `RobotConfig.WheelType`.)
  - **Wheel scale → ground clearance.** Bigger wheels spawn the chassis higher, so
    the collision box bottom clears taller low obstacles without the *body*
    scraping.
  - **Body L×W×H → collision box + tunnel test.** Height drives the tunnel
    clearance check; width/length drive stability (CoG you already compute).
- **Locomotion:** reuse `RobotControlSystem` unchanged — it drives toward a target
  with impulses and already handles step-over and fall. The finish point becomes
  the vehicle's `targetPosition`.

No motion is scripted; climb/slip/tip/fall all emerge from the solver, exactly per
your project's "prefer built-in physics" rule.

---

## 6. Collision detection & success/failure evaluation

Two cooperating pieces, both in your existing ECS style:

- **`CourseRunComponent`** on the vehicle — a telemetry bag: `startTime`,
  `maxTiltRadians`, `stalledSeconds`, `chassisHitCount`, `tunnelBlockedHits`,
  `reachedFinish`, and a final `outcome`.
- **`CourseEvaluationSystem`** (a RealityKit `System`) — each frame it updates:
  - **Finish:** horizontal distance from vehicle to the finish point < threshold →
    `reachedFinish = true`. (The finish deck also has a trigger
    `CollisionComponent` for a crisp event.)
  - **Tilt / flip:** angle between the vehicle's up-vector and world-up; a large
    sustained angle → tipped over.
  - **Stall:** near-zero horizontal velocity while still far from finish, sustained
    for N seconds → stuck.
  - **Timeout:** elapsed run time exceeds a cap with no finish → failed.

Contact *classification* ("chassis hit the rock" vs "a wheel touched it") comes
from a `CollisionEvents.Began` subscription in the coordinator: when the vehicle's
**body** collider (not the wheel visuals) contacts an entity carrying
`ObstacleMarkerComponent`, increment `chassisHitCount`; a body-vs-tunnel contact at
opening height increments `tunnelBlockedHits`. Those counters are what make the
feedback specific instead of generic.

The system resolves one of: `.success`, `.stuck`, `.chassisCollision`,
`.tooTallForTunnel`, `.flipped`, `.timeout`.

---

## 7. Engineering feedback system

`FeedbackEngine` is plain rule-based Swift — no ML — mapping the `outcome` +
telemetry + current `RobotConfig` to an `EngineeringFeedback`:

```
outcome + telemetry + config  →  { childMessage, engineeringReason, suggestedConfigChange }
```

Representative rules:

- **Stuck at a ramp/rock with low-friction tires** → *"Your wheels are slipping!
  Try grippier off-road tires."* → suggestion: set all wheels to `offroad`.
- **Chassis hit the rocks** (`chassisHitCount > 0`, wheels fine) → *"The bottom of
  your car scraped the rocks. Give it bigger wheels to lift it up."* → suggestion:
  increase `wheelScale`.
- **Blocked at the tunnel** (`tunnelBlockedHits > 0`) → *"Your car is too tall for
  the tunnel. Make it shorter."* → suggestion: reduce `bodySize.height`.
- **Tipped over** (high `maxTiltRadians`) → *"Your car flipped! Make it wider and
  lower so it's steadier."* → suggestion: increase width, lower height.
- **Too slow / timeout, no contact** → *"It didn't quite make it. Bigger wheels or
  a lighter body can help."* → suggestion: increase `wheelScale`.
- **Success** → celebrate + explain *why it worked* in one kid sentence, tying the
  win back to the change they made ("The grippy tires held onto the ramp!").

Each `suggestedConfigChange` is a function `(RobotConfig) -> RobotConfig`, so the
feedback sheet can offer a **"Fix it for me"** button that pre-applies the change
and reopens your `RobotEditorView` — the child sees the recommended edit and can
tweak from there. That is the concrete bridge from feedback (#7) back into
redesign (#8) and retest (#9).

---

## 8. What is simplified for the MVP

- **No brick recognition.** Coarse footprint blobs + one confirming tap.
- **Prop library, not reconstruction.** Fixed clean props scaled to footprint.
- **Preset heights** (LiDAR mesh height is an optional upgrade).
- **Single-body vehicle physics** — friction material stands in for a drivetrain;
  no per-wheel joints.
- **Straight-ish course** — one start pad → one finish line; obstacles between.
- **Rule-based feedback** — a lookup table, not a learned model.
- **Reuse, don't rebuild** — locomotion, config editor, and scan session already
  exist and are reused verbatim.

---

## 9. Limitations & mitigations

| Limitation | Mitigation |
|---|---|
| Height unknowable from one non-LiDAR frame | Category presets; optional LiDAR mesh sampling on capable iPads |
| Vision blob detection unreliable on cluttered tables | Human-in-the-loop confirm; require a minimum blob size; on-screen framing guide |
| RealityKit has no wheel/drivetrain physics | Approximate: single dynamic body + friction material per tire type. Good enough to *teach* grip/clearance |
| Small objects hard to detect | Ask kids to build "bigger than your fist"; enforce a min footprint |
| AR tracking drift over a long session | Keep runs short; anchor the course to the detected plane once and don't re-anchor |
| Physics looks "snappy" at tabletop scale | Optionally soften gravity via `PhysicsSimulationComponent` (you already note this) |
| Impulse locomotion can jitter on steep ramps | Cap ramp angle in `ObstacleFactory`; tune `moveSpeed`/`climbBoost` in `PhysicsRobotComponent` |

---

## 10. Recommended system flow

```
        ┌─────────────┐   detect table    ┌──────────────┐
        │  Scan table │──────────────────▶│ Frame & shoot│
        └─────────────┘  ARKit plane      └──────┬───────┘
                                                  │ Vision mask + ARKit raycast
                                                  ▼
                                        ┌───────────────────┐
                                        │ Confirm obstacles │  child taps to label
                                        │ (rock/ramp/tunnel)│  (human-in-the-loop)
                                        └─────────┬─────────┘
                                                  │ ObstacleFactory
                                                  ▼
        ┌──────────────┐   VehicleFactory  ┌───────────────────┐
        │ Customize    │◀─────────────────▶│  Build AR course  │
        │ vehicle      │   RobotConfig     │ start+obstacles+  │
        │ (tires/size) │                   │ finish line       │
        └──────┬───────┘                   └─────────┬─────────┘
               │  place vehicle                      │
               ▼                                     ▼
        ┌───────────────────────────────────────────────────┐
        │  Simulate run — RobotControlSystem drives to finish│
        │  CourseEvaluationSystem logs telemetry             │
        └───────────────────────┬───────────────────────────┘
                                ▼
                     ┌──────────────────────┐
             success │  Evaluate outcome    │  failure
          ┌──────────┤                      ├──────────┐
          ▼          └──────────────────────┘          ▼
   ┌────────────┐                              ┌──────────────────┐
   │ Celebrate  │                              │ FeedbackEngine   │
   │ + explain  │                              │ advice + "Fix it"│
   └────────────┘                              └────────┬─────────┘
                                                        │ pre-applies RobotConfig change
                                                        ▼
                                                 back to Customize  ◀── iterate
```

---

## 11. Incremental implementation roadmap

Build in vertical slices; each phase is demoable on its own.

- **Phase 0 — Course skeleton (reuse).** New `ObstacleCourseScreenView` +
  `ObstacleCourseCoordinator` cloned from `PhysicsPlaygroundCoordinator`. Tap to
  anchor an empty course on the table. *Done when* the plane + anchor work.
- **Phase 1 — Finish line & win detection.** Add `CourseFactory` (start pad +
  finish deck), `CourseRunComponent`, `CourseEvaluationSystem`. Drive the existing
  robot to the finish; detect `.success`/`.timeout`. *Done when* reaching the deck
  triggers a win.
- **Phase 2 — Hand-placed obstacles.** `ObstacleKind` + `ObstacleFactory` +
  `ObstacleMarkerComponent`. Tap-to-place clean props (no scanning yet).
  Extend evaluation to `.chassisCollision` / `.stuck` / `.tooTallForTunnel`.
- **Phase 3 — Config-driven vehicle.** `VehicleFactory` maps `RobotConfig`
  (tire→friction, wheelScale→clearance, height→tunnel test) into the physics body.
  Verify a slippery-tire car stalls where a grippy one climbs.
- **Phase 4 — Feedback loop.** `EngineeringFeedback` + `FeedbackEngine` + feedback
  sheet with "Fix it for me" that hands a mutated `RobotConfig` to
  `RobotEditorView`. Now the full iterate cycle works with *placed* obstacles.
- **Phase 5 — Real scanning.** `DetectedObstacle` + `ObstacleScanner` (Vision mask
  + ARKit raycast + confirm UI). Replace tap-to-place with scan-and-confirm.
  Start with `VNDetectRectanglesRequest` (simplest), upgrade to foreground-mask.
- **Phase 6 — Kid polish.** Sounds, celebration animation, big buttons, spoken
  feedback, optional LiDAR height. Playtest with the 6–10 target age.

Phases 0–4 need **no computer vision at all** — they're pure RealityKit on top of
what you already have, so you get a fully playable design-iteration loop before
touching Vision. Scanning (Phase 5) is then a swap-in behind `ObstacleScanner`.
