# kOS-GFOLD Architecture

This document is the implementation reference for Codex. It supersedes the longer formulation notes for project structure and public API design.

## 1. Program overview

`kOS-GFOLD` is a kOS addon that computes fuel-optimal powered-descent trajectories with GFOLD-style lossless convexification.

The addon:

- receives all body, vehicle, target, engine, and guidance data from the kOS front end;
- never reads vessel/body state from KSP/Unity APIs;
- converts the public body-fixed/body-centered state to a local landing frame;
- solves the fixed-time convex problems with **ALGLIB GENIPM only**;
- searches externally for total flight time `t_f` and pit-entry time `t_e`;
- returns time-tagged body-fixed position, velocity, thrust, and mass;
- returns a session-constant normalized discrete-LQR gain and analytically sampled reference states;
- provides synchronous APIs for testing and asynchronous APIs for flight use.

Frontend usage:

1. Before powered descent, predict the vehicle state about `gfoldInitTime = 2 s` into the future and call `Initialize` with that future state/time.
2. During powered descent, normally every `gfoldUpdateTime = 1 s`, call `Update` with the current state and the previous GFOLD result. `Update` keeps the initialization solution's absolute entry and landing epochs frozen and solves one fixed-time inner problem; it performs no time search.
3. When the previous solution has less than about `gfoldFinalTime = 3 s` remaining, stop replanning and track the latest trajectory to touchdown.

Only one solve should be active per planner session. The flight front end should not queue updates faster than they complete.

### Public units

| Quantity | Unit |
|---|---|
| Position / length | m |
| Velocity | m/s |
| Acceleration | m/s² |
| Mass | t |
| Thrust | kN |
| Time / Isp | s |
| Angles | degree |
| Body spin | rad/s |
| `mu` | m³/s² |

Using tonnes and kN is internally convenient because `1 kN / 1 t = 1 m/s²`.

---

## 2. GFOLD formulation used by this project

### 2.1 Frames and gravity model

Public vectors are body-fixed and body-centered. Internally use a local pit/target frame with:

- `x`: east;
- `y`: up;
- `z`: north.

The local origin is the pit rim/cylinder-axis center; for ordinary surface landing it is the target/reference point.

The target is the center of the cylinder floor. Therefore its local position must be
`[0, -pitDepth, 0]` within geometry tolerance. Equivalently,
`targetPosition = pitCenter - pitDepth * localUp`. In surface mode (`pitDepth = 0`),
`targetPosition` and `pitCenter` must coincide. Inconsistent geometry is rejected
as an argument error before optimization.

Let `R_LB` map body-fixed vectors to local coordinates and let `r_ref,B` be the local origin in body-fixed coordinates:

\[
p = R_{LB}(r_B-r_{\mathrm{ref},B}),\qquad
v = R_{LB}v_B.
\]

The local E-U-N frame is left-handed. Do **not** assume that the usual right-handed skew matrix remains valid after the coordinate transform. Build the physical rotation operator in the body-fixed frame and transform the operator itself.

For spherical gravity,

\[
a_g(r)=-\mu\frac{r}{\|r\|^3},
\]

and at the reference point

\[
J_{g,B}=\frac{\mu}{R^3}(3nn^T-I),\qquad
R=\|r_{\mathrm{ref},B}\|,\quad
n=\frac{r_{\mathrm{ref},B}}{R}.
\]

Let `Omega_B` be the linear operator satisfying

\[
\Omega_B q = \omega_B\times q
\]

under the body-fixed vector convention. Define

\[
A_p=R_{LB}(J_{g,B}-\Omega_B^2)R_{BL},
\]

\[
A_v=-2R_{LB}\Omega_B R_{BL},
\]

\[
g_0=R_{LB}\left(-\mu\frac{r_{\mathrm{ref},B}}{R^3}-\Omega_B^2r_{\mathrm{ref},B}\right).
\]

The optimizer therefore uses the LTI model

\[
\dot p=v,
\]

\[
\dot v=A_p p+A_v v+g_0+\frac{T}{m}.
\]

Exact central gravity is not part of the SOCP. It is used only for post-solve validation.

### 2.2 Engine modes and mass flow

There are two engine modes. `t_c` is fixed by the user at initialization.

\[
j(t)=\begin{cases}1,&t<t_c,\\2,&t\ge t_c.\end{cases}
\]

For mode `j`:

\[
0<\rho_1^{(j)}\le \|T\|_2\le\rho_2^{(j)},
\]

\[
\alpha_j=\frac{1}{I_{sp,j}g_{\mathrm{std}}},\qquad g_{\mathrm{std}}=9.80665\;\mathrm{m/s^2},
\]

\[
\dot m=-\alpha_j\|T\|_2.
\]

The engine-switch epoch is stored in the planner session. On an `Update`, the remaining switch time is recomputed from the new state epoch. If the switch has already occurred, the remaining trajectory uses mode 2 only.

### 2.3 Lossless convexification

Introduce relaxed thrust magnitude `Gamma` and transformed variables

\[
u=\frac{T}{m},\qquad
\sigma=\frac{\Gamma}{m},\qquad
\zeta=\ln\frac{m}{m_0}.
\]

Then

\[
\dot p=v,
\]

\[
\dot v=A_p p+A_v v+g_0+u,
\]

\[
\dot\zeta=-\alpha_j\sigma.
\]

At every constrained sample:

\[
\|u\|_2\le\sigma.
\]

For a maximum tilt angle `theta` from local up, with `e_y=[0,1,0]^T`, use

\[
e_y^T u\ge\sigma\cos\theta.
\]

The physical lower/upper thrust bounds become mass-dependent. Use the GFOLD conservative approximation around the maximum-thrust reference mass.

Define

\[
m_-(t)=m_0-\int_0^t\alpha_{j(s)}\rho_2^{(j(s))}\,ds,
\]

\[
\zeta_0(t)=\ln\frac{m_-(t)}{m_0},\qquad
\delta=\zeta-\zeta_0,
\]

\[
\mu_1=\frac{\rho_1^{(j)}}{m_0}e^{-\zeta_0},\qquad
\mu_2=\frac{\rho_2^{(j)}}{m_0}e^{-\zeta_0}.
\]

Then impose

\[
\mu_1\left(1-\delta+\frac{\delta^2}{2}\right)\le \sigma\le\mu_2(1-\delta).
\]

The upper inequality is linear and the convex quadratic lower inequality is encoded as an SOC.

### 2.4 Guidance phases

Pit entry time `t_e` is an outer-search variable:

\[
q(t)=\begin{cases}D,&t<t_e,\\E,&t\ge t_e.\end{cases}
\]

For fixed `t_e` and `t_f`, all phase assignments are constants, so the inner problem remains an SOCP. The engine mode switch `t_c` and guidance phase switch `t_e` are independent.

### 2.5 Path constraints

Let

\[
p_h=[p_x,p_z]^T,\qquad R_s=R_{\mathrm{pit}}-b_{\mathrm{wall}}.
\]

**Descent / outside pit**

\[
p_y\ge0,
\]

\[
p_y\ge\tan\gamma_D(\|p_h\|_2-R_s),
\]

\[
\|v\|_2\le V_{\max,D},
\]

\[
e_y^Tu\ge\sigma\cos\theta_D.
\]

**Entry / inside pit**

For pit depth `H`:

\[
\|p_h\|_2\le R_s,
\]

\[
-H\le p_y\le0,
\]

\[
v_y\le0,
\]

\[
\|v\|_2\le V_{\max,E},
\]

\[
e_y^Tu\ge\sigma\cos\theta_E.
\]

The phase-2 inner glide slope is

\[
\tan\gamma_E\|p_h-p_{f,h}\|_2\le p_y-p_{f,y}.
\]

A value of `gamma_E = 0` effectively disables the extra inner cone beyond the cylinder/floor constraints.

**Terminal tilt window**

For all samples whose time-to-go is within `terminalTiltWindow`:

\[
e_y^Tu\ge\sigma\cos\theta_{\mathrm{terminal}}.
\]

This is a thrust-direction proxy for upright terminal attitude; no rigid-body attitude dynamics are modeled.

If `pitDepth = 0`, treat the problem as surface landing: set `t_e=t_f`, omit the entry phase, and search only over `t_f`.

### 2.6 Boundary, fuel, and two-stage objective

Initial conditions:

\[
p(0)=p_0,\qquad v(0)=v_0,\qquad \zeta(0)=0.
\]

Dry mass:

\[
m_{\mathrm{dry}}=m_0-m_{\mathrm{fuel}},
\]

\[
\zeta(t_f)\ge\ln\frac{m_{\mathrm{dry}}}{m_0}.
\]

The final velocity and final vertical coordinate are fixed:

\[
v(t_f)=v_f,
\]

\[
e_y^Tp(t_f)=e_y^Tp_f.
\]

For each fixed `(t_f,t_e)`, solve two SOCPs.

**P1 — minimum landing error**

\[
\min d
\]

subject to all constraints and

\[
\|p_h(t_f)-p_{f,h}\|_2\le d.
\]

Let the optimum be `d*`.

**P2 — minimum fuel at minimum landing error**

\[
\min -\zeta(t_f)
\]

subject to all constraints and

\[
\|p_h(t_f)-p_{f,h}\|_2\le d^*.
\]

If `d*=0` within tolerance, the target is reached exactly. Otherwise the result is the closest reachable landing point on the target-height plane.

### 2.7 Discretization and normalization

Use a nonuniform event-aligned mesh containing every active event:

\[
\{0,t_c,t_e,t_f\}.
\]

State and mass are continuous across events. Control is **not** forced continuous across `t_c` or `t_e`; use independent left/right `(u,sigma)` variables at event nodes.

`nodes` is the exact total number of major state nodes, including event nodes.
Each event-separated segment receives at least one interval; remaining intervals
are distributed in proportion to segment duration using deterministic largest-remainder
allocation.

Between events the dynamics are LTI. Use first-order-hold control. For interval duration `h`:

\[
x_{k+1}=\Phi(h)x_k+\Gamma_0(h)u_k+\Gamma_1(h)u_{k+1}+\gamma(h),
\]

where `Phi`, `Gamma0`, `Gamma1`, and `gamma` are computed from the matrix exponential of the LTI system.

For log mass:

\[
\zeta_{k+1}=\zeta_k-\frac{\alpha_j h}{2}(\sigma_k+\sigma_{k+1}).
\]

Apply path constraints at major nodes and at least the midpoint of every interval using affine midpoint state expressions.

Normalize every solver-facing problem. Use

\[
M=m_0,
\]

\[
L=\max(\|p_0-p_f\|,R_{\mathrm{pit}},H,L_{\min}),
\]

\[
a_*=\max(\|g_0\|,\rho_{2,\max}/m_0,\|v_0\|^2/L,a_{\min}),
\]

\[
T_*=\sqrt{L/a_*},\qquad V_*=\sqrt{La_*}.
\]

Scale position by `L`, velocity by `V_*`, acceleration / `u` / `sigma` by `a_*`, and time by `T_*`. `zeta` is already dimensionless.

### 2.8 Outer time search

`t_f` and `t_e` are not SOCP variables. For pit landing search `(t_f,s)` with

\[
s=t_e/t_f,\qquad 0<s<1.
\]

During `Initialize`, use a deterministic coarse-to-fine search with a default budget of **20 time candidates**. Each hard candidate requires P1 and P2.

Rank candidates lexicographically: minimum horizontal landing error first, then
minimum fuel for candidates tied within landing-error tolerance, then deterministic
evaluation order. Surface cold searches use a seven-point grid followed by bracket
refinement. Pit cold searches use a `4 x 3` `(t_f,s)` grid followed by half-spacing
refinement.

`Initialize` performs the cold search.

After a successful initialization, freeze the absolute landing and entry epochs:

\[
T_f=\text{initial epoch}+t_f^{\mathrm{initial}},
\]

\[
T_e=\text{initial epoch}+t_e^{\mathrm{initial}}.
\]

Every `Update` uses exactly

\[
t_f=T_f-\text{current stateTime},\qquad
t_e=T_e-\text{current stateTime},
\]

and runs one hard P1/P2 pair followed by validation. It performs no local or cold
outer search and never changes `T_f` or `T_e`. If pit entry has already occurred,
return `t_e=0` and solve only the entry phase. A failed fixed-time inner solve is
returned directly; it is not converted to `TIME_BUDGET_EXCEEDED` by the outer-search
watchdog.

Search-only soft constraints may be used to rank otherwise infeasible time candidates, but every returned trajectory must come from the hard P1/P2 problems and pass physical validation.

The two-second watchdog is soft because ALGLIB cannot interrupt an active GENIPM
call. Check it only between complete P1/P2 candidate pairs. If the deadline is
reached after a validated candidate exists, return that best candidate as `SOLVED`
and record the early search termination in `message`.

### 2.9 Reference tracking and normalized discrete LQR

The tracking input is specific thrust `u=T/m`, in `m/s^2`. The public state error is

\[
e=[r_{ref}-r;\ v_{ref}-v],\qquad u=u_{ref}+K e.
\]

At initialization, freeze a tracker normalizer using the same `L`, `a_*`, `T_*`, and
`V_*` rules as the solver. Later replans may use different solver normalizers, but
the tracker scale and gain never change during the session. In normalized local
coordinates, exactly discretize the error dynamics at `lqrDt/T_*` with zero-order-held
control correction and solve the infinite-horizon discrete Riccati equation with

\[
Q=\operatorname{diag}(I_3,\beta I_3),\qquad R=\lambda I_3.
\]

Convert the resulting normalized gain through the position, velocity, acceleration,
and E-U-N/body transformations. The returned `K` therefore acts directly on physical
body-fixed errors and produces a body-fixed acceleration correction. Raw LQR output
is not projected into thrust or tilt limits; the flight frontend owns actuator limiting.

Every interval retains its outgoing left control `u_i^+` and incoming right control
`u_{i+1}^-`. For `tau=t-t_i` and `h=t_{i+1}-t_i`,

\[
u_{ref}(t)=u_i^+ + \frac{\tau}{h}(u_{i+1}^- - u_i^+).
\]

The reference state is evaluated analytically from node `i` with the same affine LTI
FOH matrix exponential used by the optimizer. At an exact internal node the control
is right-continuous; at the terminal node the incoming control is returned.

---

## 3. Project architecture

Recommended layout:

```text
src/kOS-GFOLD/
  GFOLDAddon.cs
  Core/
    Models.cs
    Planner.cs
    FrameModel.cs
    Normalizer.cs
    MeshBuilder.cs
    LtiDiscretizer.cs
    LqrTracker.cs
    TimeSearch.cs
    GfoldProblemBuilder.cs
    AlglibSocpSolver.cs
    SolutionValidator.cs
```

The implementation also includes `kOS-GFOLD.Cli`, which compiles the same plain
`Core/*.cs` sources without referencing kOS, Unity, or KSP. This keeps command-line
testing numerically identical to the addon without adding another runtime DLL.

### `GFOLDAddon`

kOS-facing wrapper only.

Responsibilities:

- register synchronous/asynchronous suffixes;
- parse/validate kOS `Lexicon`, `Vector`, `ListValue`, and scalar values;
- copy all input into plain immutable DTOs before background work;
- maintain task handles;
- convert plain results back to kOS values.

It must not contain optimization math.

Follow the `kOS-AFS` async pattern:

- static `ConcurrentDictionary<int, TaskRecord>`;
- handles generated with `Interlocked.Increment`;
- numerical work launched with `Task.Run`;
- `CheckTask(handle)` tests completion;
- `GetTaskResult(handle)` returns and removes the completed task result.

### `PlannerSession`

Immutable configuration created by `Initialize`:

- body/frame parameters;
- target and pit geometry;
- dry mass;
- engine-mode parameters;
- absolute engine-switch epoch;
- path-constraint parameters;
- node count and search settings;
- frozen tracker normalization, LQR weights/sample period, and physical body-fixed gain.

A session receives an integer `session` ID returned in every solution. `Update` uses this ID and does not require the caller to resend static configuration.

### `Planner`

Owns `Initialize`, `Update`, and reference-state sampling.

`Initialize`:

1. construct local frame and gravity-gradient model;
2. normalize;
3. perform cold outer time search;
4. solve P1/P2 for the best candidate;
5. validate;
6. return trajectory and session ID.

`Update`:

1. load immutable session;
2. transform current state into the same local frame;
3. compute remaining engine-switch time from the stored switch epoch;
4. derive remaining entry and landing durations from the session-frozen absolute epochs;
5. solve exactly one fixed-time P1/P2 pair, without an outer search;
6. validate and return a replacement trajectory.

### `FrameModel`

- body-fixed ↔ local E-U-N transform;
- `mu`, gravity-gradient, Coriolis, and centrifugal matrices;
- exact central-gravity propagation for validation only.

### `Normalizer`

Builds scaling factors and converts all solver data/result variables.

### `MeshBuilder`

Builds the event-aligned nonuniform mesh and left/right control variables at `t_c` / `t_e`.

### `LtiDiscretizer`

Computes FOH discrete matrices and affine midpoint maps.

### `LqrTracker`

Exactly discretizes the normalized error model, solves the steady-state discrete
Riccati equation, converts the gain to physical body-fixed coordinates, and evaluates
FOH reference state/control samples analytically.

### `TimeSearch`

- 1D search for surface landing;
- 2D `(t_f,s)` search for pit landing;
- default 20 candidate evaluations for cold initialization only.

`Update` bypasses `TimeSearch` and sends one session-frozen time candidate directly
to the inner P1/P2 solver.

### `GfoldProblemBuilder`

Creates P1/P2 as sparse affine equalities, linear inequalities, and second-order cones. It has no kOS/KSP dependency.

### `AlglibSocpSolver`

The **only** solver backend.

- use ALGLIB GENIPM;
- prefer the sparse formulation;
- reuse problem structure and allocated data where practical;
- no alternative SOCP backend;
- solver failure is returned as a planner status, not silently converted into a trajectory.

### `SolutionValidator`

After de-normalization:

- reconstruct physical `T=m u`;
- check original thrust bounds;
- check tilt, speed, pit/glide-slope, fuel, and terminal constraints;
- check `| ||u|| - sigma |`;
- propagate with exact central gravity and reject excessive model/trajectory error.

A result that fails validation is never returned as `SOLVED`.

### Threading rules

- No KSP/Unity/kOS runtime object may be accessed from a worker thread.
- Parse and snapshot all arguments before `Task.Run`.
- Use one active solve per planner session.
- The front end should call `Update` only after the previous async update has completed.
- Old/stale results must never replace a newer accepted trajectory.

---

## 4. Public API

The addon name is assumed to be `GFOLD`. All complex arguments/results are kOS `Lexicon` objects.

### 4.1 `Initialize(args) -> Lexicon`

Synchronous cold initialization. Intended mainly for tests/debugging; it blocks the caller.

`args` fields:

| Field | Type | Unit | Description |
|---|---|---:|---|
| `stateTime` | Scalar | s | Epoch of the supplied initial state. Normally the frontend-predicted state about 2 s in the future. |
| `position` | Vector | m | Initial body-fixed/body-centered position. |
| `velocity` | Vector | m/s | Initial body-fixed velocity. |
| `mass` | Scalar | t | Initial mass at `stateTime`. |
| `mu` | Scalar | m³/s² | Body gravitational parameter. |
| `bodyRadius` | Scalar | m | Body reference radius. |
| `bodySpin` | Vector | rad/s | Body-fixed angular-velocity vector. |
| `targetPosition` | Vector | m | Target body-fixed/body-centered position. |
| `targetVelocity` | Vector | m/s | Target body-fixed velocity. |
| `pitCenter` | Vector | m | Pit rim/cylinder-axis center; local-frame origin. For surface landing use the target/reference point. |
| `fuelMass` | Scalar | t | Usable fuel mass. `dryMass = mass - fuelMass`. |
| `thrustMin1` | Scalar | kN | Engine-mode-1 minimum thrust. |
| `thrustMax1` | Scalar | kN | Engine-mode-1 maximum thrust. |
| `isp1` | Scalar | s | Engine-mode-1 Isp. |
| `thrustMin2` | Scalar | kN | Engine-mode-2 minimum thrust. |
| `thrustMax2` | Scalar | kN | Engine-mode-2 maximum thrust. |
| `isp2` | Scalar | s | Engine-mode-2 Isp. |
| `engineSwitchTime` | Scalar | s | Time after `stateTime` at which mode 1 changes to mode 2. Stored internally as an absolute epoch. |
| `descentMaxSpeed` | Scalar | m/s | Phase-D maximum speed. |
| `descentTilt` | Scalar | deg | Phase-D maximum thrust tilt from up. |
| `descentGlideSlope` | Scalar | deg | Outside-pit glide-slope angle. |
| `entryMaxSpeed` | Scalar | m/s | Phase-E maximum speed. |
| `entryTilt` | Scalar | deg | Phase-E maximum thrust tilt from up. |
| `entryGlideSlope` | Scalar | deg | Inner glide-slope angle; `0` disables the extra inner cone. |
| `terminalTilt` | Scalar | deg | Maximum tilt during terminal window. |
| `terminalTiltWindow` | Scalar | s | Time-to-go interval over which `terminalTilt` applies. |
| `pitRadius` | Scalar | m | Physical pit/cylinder radius. |
| `wallBuffer` | Scalar | m | Required radial wall clearance. |
| `pitDepth` | Scalar | m | Rim-to-floor height. `0` selects surface-landing mode. |
| `nodes` | Scalar integer | — | Number of major state nodes; nominal value 20. |
| `maxSearchEvaluations` | Scalar integer | — | Optional cold outer-search candidate budget; default 20. |
| `tfMin` | Scalar | s | Optional lower total-flight-time bound. If omitted, derive a conservative bound. |
| `tfMax` | Scalar | s | Optional upper total-flight-time bound. If omitted, derive a fuel/thrust bound. |
| `lqrDt` | Scalar | s | Required positive controller sample period used for exact LQR discretization. |
| `lqrLambda` | Scalar | — | Optional positive normalized control weight `lambda`; default `0.5`. |
| `lqrBeta` | Scalar | — | Optional nonnegative normalized velocity weight `beta`; default `1`. |

Validation errors in the argument schema throw a `KOSException` before solving.

### 4.2 `AsyncInitialize(args) -> integer handle`

Asynchronous version of `Initialize`.

- Parse/snapshot `args` synchronously.
- Start the same `Initialize` core on a background worker.
- Return an integer task handle immediately.
- Retrieve the final result with `CheckTask` / `GetTaskResult`.

This is the normal flight API for the initial trajectory.

### 4.3 `Update(args) -> Lexicon`

Synchronous receding-horizon update. It blocks the caller and is intended mainly for tests/debugging.

`args` fields:

| Field | Type | Unit | Description |
|---|---|---:|---|
| `session` | Scalar integer | — | Session ID returned by `Initialize`. |
| `stateTime` | Scalar | s | Epoch of the current measured/predicted state, using the same clock as initialization. |
| `position` | Vector | m | Current body-fixed/body-centered position. |
| `velocity` | Vector | m/s | Current body-fixed velocity. |
| `mass` | Scalar | t | Current mass. |
| `previous` | Lexicon | — | Previous successful `Initialize`/`Update` result, including trajectory and `t_e/t_f`. |

`Update` does **not** accept new body, engine, target, pit, guidance, or LQR configuration. Those remain fixed in the session.

Behavior:

- derive remaining `t_f`, `t_e`, and engine-switch timing from the absolute event epochs frozen by `Initialize`;
- verify that `previous` belongs to the latest successful update chain and preserves those event epochs;
- solve exactly one hard fixed-time P1/P2 pair and validate it;
- if the pit has already been entered, solve only the entry phase;
- return an inner-solver failure directly without attempting another time candidate;
- return a complete replacement trajectory from the new `stateTime`.

The frontend should normally stop calling `Update` when the previous trajectory has less than about 3 s remaining.

### 4.4 `AsyncUpdate(args) -> integer handle`

Asynchronous version of `Update`; this is the normal in-flight replan API.

It follows the same task-handle behavior as `AsyncInitialize`.

Do not launch a second update for the same session while a previous update task is still running.

### 4.5 Task management

#### `CheckTask(handle) -> Boolean`

Returns `true` when the task has finished, regardless of whether the solve succeeded. Solver success/failure is reported in the task result.

Invalid handles throw `KOSException`.

#### `GetTaskResult(handle) -> Lexicon`

- requires a completed task;
- returns the same result schema as the synchronous API;
- removes the task record after retrieval;
- throws `KOSException` for an invalid handle or an unfinished task.

This intentionally matches the task-management style used by `kOS-AFS`.

### 4.6 `GetRefState(args) -> Lexicon`

Analytically samples a successful reference returned by this planner instance.

| Field | Type | Unit | Description |
|---|---|---:|---|
| `reference` | Lexicon | — | Complete successful `Initialize`/`Update` result, including its session and trajectory. |
| `time` | Scalar | s | Absolute sample epoch, inclusively bounded by the first and last trajectory nodes. |

The result contains `time`, body-fixed `control` in `m/s^2`, body-fixed/body-centered
`position` in metres, and body-fixed `velocity` in `m/s`. Invalid, out-of-range,
malformed, failed, or unknown-session references throw `KOSException`.

### 4.7 Result schema

`Initialize`, `Update`, and `GetTaskResult` return the same top-level schema:

| Field | Type | Description |
|---|---|---|
| `ok` | Boolean | `true` only for a validated usable trajectory. |
| `status` | String | `SOLVED`, `INFEASIBLE`, `NUMERICAL_FAILURE`, `VALIDATION_FAILED`, `TIME_BUDGET_EXCEEDED`, or `CANCELLED`. |
| `message` | String | Short diagnostic text. |
| `session` | Scalar integer | Planner session ID. |
| `epoch` | Scalar | `stateTime` from which this trajectory starts. |
| `solveTime` | Scalar | Total wall-clock planning time in seconds. |
| `tf` | Scalar | Remaining total flight time from `epoch`. |
| `te` | Scalar | Remaining pit-entry time from `epoch`; for surface mode `te=tf`. |
| `landingError` | Scalar | P1 horizontal landing error in metres. |
| `fuelUsed` | Scalar | Fuel consumed by the returned trajectory in tonnes. |
| `searchEvaluations` | Scalar integer | Number of time candidates tested; exactly 1 for an `Update` that reaches the inner solver. |
| `K` | List of 3 Lists | Session-constant physical body-fixed 3 by 6 LQR gain; present only when `ok=true`. |
| `trajectory` | List | Major-node trajectory described below. |

Each `trajectory` element is a Lexicon:

| Field | Type | Unit | Description |
|---|---|---:|---|
| `time` | Scalar | s | Absolute node epoch using the same clock as `stateTime`. |
| `position` | Vector | m | Body-fixed/body-centered position. |
| `velocity` | Vector | m/s | Body-fixed velocity. |
| `thrust` | Vector | kN | Body-fixed commanded physical thrust vector. |
| `mass` | Scalar | t | Predicted mass. |
| `controlBefore` | Vector | m/s² | Incoming body-fixed specific thrust for the interval ending at this node. |
| `controlAfter` | Vector | m/s² | Outgoing body-fixed specific thrust for the interval starting at this node. |

A non-`SOLVED` result may omit `trajectory`, `K`, `tf`, and `te`.

### 4.8 Command-line numerical API

The standalone wrapper supports:

```text
kOS-GFOLD.Cli.exe solve --input scenario.json [--output result.json]
kOS-GFOLD.Cli.exe sequence --input sequence.json [--output result.json]
kOS-GFOLD.Cli.exe selftest
```

`solve` uses the `Initialize` field names, including `lqrDt`, with vectors encoded as three-element JSON
arrays. `sequence` contains an `initialize` object and an ordered `updates` array;
the process retains the planner session and automatically uses each successful result
as the next accepted-chain reference. JSON is written to standard output when `--output` is omitted.
Exit codes are `0` for success, `2` for a planner failure, `64` for invalid input, and
`70` for an unexpected internal error.

`tests/Test-Gfold.ps1` builds and exercises the CLI. `tools/analyze_gfold.py`
independently checks constraint margins and exact rotating-frame propagation with
NumPy/SciPy and produces trajectory and constraint plots with Matplotlib.

---

## 5. Implementation constraints

1. Use **ALGLIB GENIPM only**. Do not implement or maintain another SOCP backend.
2. Use sparse problem assembly and mandatory normalization.
3. `nodes = 20` is the nominal performance case.
4. Performance target: a complete 20-node cold initialization with about 20 outer time candidates (P1 + P2 per hard candidate) should finish in about **1 s** on a normal desktop KSP installation; **2 s** is the initialization-search watchdog/failure ceiling. Periodic `Update` should be faster because it runs one fixed-time P1/P2 pair.
5. Background solving is mandatory for flight use.
6. The addon must contain no direct vessel/body KSP state acquisition.
7. The previous trajectory identifies the accepted update chain and must preserve the session-frozen event epochs; every update independently satisfies and validates the current fixed-time hard problem.
8. The final few seconds are tracking-only by frontend policy, not a special solver mode.
9. Do not add aerodynamic drag, rigid-body attitude dynamics, thrust-direction slew constraints, or integer engine decisions to this version.


---

## 6. Design basis

- B. Acikmese, J. M. Carson III, L. Blackmore, *Lossless Convexification of Nonconvex Control Bound and Pointing Constraints of the Soft Landing Optimal Control Problem* (2013).
- N. S. Bhasin, *Fuel-Optimal Spacecraft Guidance for Landing in Planetary Pits* (2016).
- kOS async/task API pattern: `Chris_KSP_Lib/src/kOS-AFS/kOS-AFS/AFSAddon.cs` on GitHub.
