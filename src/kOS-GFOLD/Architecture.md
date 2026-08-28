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
- provides synchronous APIs for testing and asynchronous APIs for flight use.

Frontend usage:

1. Before powered descent, predict the vehicle state about `gfoldInitTime = 2 s` into the future and call `Initialize` with that future state/time.
2. During powered descent, normally every `gfoldUpdateTime = 1 s`, call `Update` with the current state and the previous GFOLD result. `Update` uses the previous solution to seed the new time search.
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

Use a deterministic coarse-to-fine search with a default budget of **20 time candidates**. Each hard candidate requires P1 and P2.

`Initialize` performs the cold search.

`Update` centers a local search on the remaining times from the previous result:

\[
t_{f,\mathrm{guess}}=(\text{previous epoch}+t_f^{\mathrm{previous}})-\text{current stateTime},
\]

\[
t_{e,\mathrm{guess}}=(\text{previous epoch}+t_e^{\mathrm{previous}})-\text{current stateTime}.
\]

If entry has already occurred, omit the `t_e` search and solve the entry phase only. If the local search fails, fall back to the bounded cold search within the configured evaluation budget.

Search-only soft constraints may be used to rank otherwise infeasible time candidates, but every returned trajectory must come from the hard P1/P2 problems and pass physical validation.

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
    TimeSearch.cs
    GfoldProblemBuilder.cs
    AlglibSocpSolver.cs
    SolutionValidator.cs
```

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
- node count and search settings.

A session receives an integer `session` ID returned in every solution. `Update` uses this ID and does not require the caller to resend static configuration.

### `Planner`

Owns `Initialize` and `Update` computation.

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
4. use the previous trajectory/times to seed the local outer search;
5. solve P1/P2;
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

### `TimeSearch`

- 1D search for surface landing;
- 2D `(t_f,s)` search for pit landing;
- default 20 candidate evaluations for cold initialization;
- local search around previous `t_f,t_e` for updates.

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
| `maxSearchEvaluations` | Scalar integer | — | Optional local-search budget. If omitted, use the session default. |

`Update` does **not** accept new body, engine, target, pit, or guidance configuration. Those remain fixed in the session.

Behavior:

- derive remaining `t_f`, `t_e`, and engine-switch timing from `previous`, `stateTime`, and the session;
- use the previous trajectory/times as the search seed;
- if the pit has already been entered, solve only the entry phase;
- if the local search fails, fall back to a bounded cold search;
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

### 4.6 Result schema

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
| `searchEvaluations` | Scalar integer | Number of outer time candidates tested. |
| `trajectory` | List | Major-node trajectory described below. |

Each `trajectory` element is a Lexicon:

| Field | Type | Unit | Description |
|---|---|---:|---|
| `time` | Scalar | s | Absolute node epoch using the same clock as `stateTime`. |
| `position` | Vector | m | Body-fixed/body-centered position. |
| `velocity` | Vector | m/s | Body-fixed velocity. |
| `thrust` | Vector | kN | Body-fixed commanded physical thrust vector. |
| `mass` | Scalar | t | Predicted mass. |

A non-`SOLVED` result may omit `trajectory`, `tf`, and `te`.

---

## 5. Implementation constraints

1. Use **ALGLIB GENIPM only**. Do not implement or maintain another SOCP backend.
2. Use sparse problem assembly and mandatory normalization.
3. `nodes = 20` is the nominal performance case.
4. Performance target: a complete 20-node cold initialization with about 20 outer time candidates (P1 + P2 per hard candidate) should finish in about **1 s** on a normal desktop KSP installation; **2 s** is the watchdog/failure ceiling. Periodic `Update` should normally be faster because it starts from the previous time solution.
5. Background solving is mandatory for flight use.
6. The addon must contain no direct vessel/body KSP state acquisition.
7. The previous trajectory is a seed, never a correctness requirement; every update must independently satisfy and validate the current hard problem.
8. The final few seconds are tracking-only by frontend policy, not a special solver mode.
9. Do not add aerodynamic drag, rigid-body attitude dynamics, thrust-direction slew constraints, or integer engine decisions to this version.


---

## 6. Design basis

- B. Acikmese, J. M. Carson III, L. Blackmore, *Lossless Convexification of Nonconvex Control Bound and Pointing Constraints of the Soft Landing Optimal Control Problem* (2013).
- N. S. Bhasin, *Fuel-Optimal Spacecraft Guidance for Landing in Planetary Pits* (2016).
- kOS async/task API pattern: `Chris_KSP_Lib/src/kOS-AFS/kOS-AFS/AFSAddon.cs` on GitHub.
