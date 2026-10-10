# KSP atmosphere mathematics used by kOS-ATM

This model is reconstructed from the installed KSP 1.12.5 assembly, rather than inferred from API names or fitted to flight data. Its pressure, temperature composition and ideal-gas conversion are understood. The loaded body configuration supplies numerical curves; their values are inputs to the model, not an unknown algorithm. RSS/RO changes those inputs, and FAR's atmosphere registration is a separate interface.

The equations below describe [AtmosphereSnapshot.cs](AtmosphereSnapshot.cs), with geometry captured by [AtmosphereCapture.cs](AtmosphereCapture.cs) and numerical operations in [ManagedMath.cs](ManagedMath.cs). Current-epoch thermal equations have in-game validation. Future geometry uses a managed Kepler/rotation extension with offline tests and capture-time checks against KSP; complete future-time atmosphere parity still needs in-game validation. See [research results](../KSP-AtmosphereResearch/docs/ResultsSummary.md) for measurements and limits.

## 1. Inputs, units and overall equation

Let the requested location have latitude $\phi$, longitude $\lambda$, altitude $h$ above the body's spherical sea-level radius $R_b$, and universal time $t$. A snapshot has epoch $t_0$ and elapsed time $\tau=t-t_0$.

| Symbol | Meaning | Unit |
| --- | --- | --- |
| $h,R_b,H_a$ | Altitude, body radius, atmosphere depth | m |
| $p$ | Internal KSP static pressure | kPa |
| $P=1000p$ | Public pressure | Pa |
| $T,T_0,\Delta T$ | Ambient temperature, altitude baseline, thermal offset | K |
| $\rho$ | Mass density | kg/m³ |
| $M_g$ | `atmosphereMolarMass` | kg/mol |
| $\mathcal R$ | `PhysicsGlobals.IdealGasConstant` | J/(mol K) |

Angles in trigonometric equations are radians; curve arguments for latitude and orbital anomaly are degrees. The kOS geographic API accepts degrees and absolute UT. The C# position API accepts elapsed seconds and a body-centered position in the snapshot's body-fixed frame.

Within the atmosphere, the composition is

$$
\boxed{P(h)=1000p(h),\qquad
T(h,\phi,\lambda,t)=T_0(h)+U(h)\Delta T(\phi,\lambda,h,t),\qquad
\rho=\frac{P M_g}{\mathcal R T}.}
$$

$U$ is the loaded `atmosphereTemperatureSunMultCurve`. Pressure has no explicit latitude, longitude or season dependence in this KSP model. Density acquires those dependencies through temperature. At identical pressure, $\rho_2/\rho_1=T_1/T_2$.

`temperature_offset` returns $\Delta T$, before multiplication by $U(h)$. It is not the final temperature correction.

## 2. The eight loaded curves

Each function below evaluates copied keys from the corresponding body's curve. None is a universal Earth or Kerbin constant.

| Function | KSP field | Input | Output |
| --- | --- | --- | --- |
| $C_p$ | `atmospherePressureCurve` | $h$ or $h/H_a$ | kPa or normalized fraction |
| $C_T$ | `atmosphereTemperatureCurve` | $h$ or $h/H_a$ | K or normalized fraction |
| $U$ | `atmosphereTemperatureSunMultCurve` | $h$ | Dimensionless multiplier |
| $B$ | `latitudeTemperatureBiasCurve` | Absolute thermal latitude, degrees | K |
| $L$ | `latitudeTemperatureSunMultCurve` | Absolute thermal latitude, degrees | K |
| $S$ | `axialTemperatureSunBiasCurve` | Reference orbit true anomaly, degrees | K |
| $A$ | `axialTemperatureSunMultCurve` | Absolute thermal latitude, degrees | Dimensionless multiplier |
| $C_e$ | `eccentricityTemperatureBiasCurve` | Periapsis-to-apoapsis distance fraction | K |

The curve names containing “mult” do not all have the same units: $L$ multiplies a dimensionless solar factor and therefore contributes kelvin.

### Curve evaluation

For adjacent keys $(x_i,y_i)$ and $(x_{i+1},y_{i+1})$, let $d=x_{i+1}-x_i$, $v=(x-x_i)/d$, $m_i$ be the first key's outgoing tangent and $m_{i+1}$ the second key's incoming tangent. The unweighted cubic Hermite segment is

$$
C(x)=(2v^3-3v^2+1)y_i+(v^3-2v^2+v)d m_i
       +(-2v^3+3v^2)y_{i+1}+(v^3-v^2)d m_{i+1}.
$$

Tangents are derivatives with respect to the curve's input, so the interval length $d$ is required. Inputs outside the keys clamp to the endpoint value. An infinite relevant tangent produces a step: the left value throughout the segment, then the right value at its key. An empty curve evaluates to zero.

kOS-ATM copies unweighted, nonlooping curves and rejects weighted keys or Loop/PingPong wrapping. Hermite arithmetic uses double intermediates and returns float, matching the precision of the source values without calling Unity's shared `AnimationCurve.Evaluate`. This is interpolation of KSP's actual configuration curves, not a new atmosphere table fitted from flight samples.

## 3. Altitude pressure and baseline temperature

Define $\operatorname{sat}(x)=\min(1,\max(0,x))$. The pressure branch is

$$
p(h)=
\begin{cases}
C_p(h), & \text{unnormalized pressure curve},\\
p_{sl}\operatorname{sat}(C_p(h/H_a)), & \text{normalized pressure curve},\\
p_{sl}\left(1-\dfrac{\ell h}{T_{sl}}\right)^G, & \text{pressure curve disabled}.
\end{cases}
$$

Here $p_{sl}$ is `atmospherePressureSeaLevel`, $T_{sl}$ is `atmosphereTemperatureSeaLevel`, $\ell$ is `atmosphereTemperatureLapseRate`, and $G$ is the loaded `atmosphereGasMassLapseRate`. The port uses $G$ as supplied; it does not recompute it from gravity or molar mass.

The baseline temperature is

$$
T_0(h)=
\begin{cases}
C_T(h), & \text{unnormalized temperature curve},\\
(1-c)T_{space}+cT_{sl},\quad c=\operatorname{sat}(C_T(h/H_a)), & \text{normalized temperature curve},\\
T_{sl}-\ell h, & \text{temperature curve disabled}.
\end{cases}
$$

$T_{space}$ is the captured `PhysicsGlobals.SpaceTemperature`. The normalized pressure multiplication uses float precision; the normalized temperature interpolation uses the installed double `UtilMath.Lerp` expression. These branches describe game behavior, not a continuously re-integrated hydrostatic atmosphere. In particular, changing local temperature does not cause KSP to recompute the pressure curve.

## 4. Location and Sun direction

Capture three geographic unit vectors in raw world axes: north $\mathbf n$, equatorial longitude-zero $\mathbf e_0$, and equatorial longitude-90° $\mathbf e_{90}$. They come from `GetWorldSurfacePosition` minus body position, so the body's orientation and tilt are included. The initial radial unit vector for geographic coordinates is

$$
\mathbf u_0=\mathbf n\sin\phi+
 (\mathbf e_0\cos\lambda+\mathbf e_{90}\sin\lambda)\cos\phi.
$$

For a trajectory position $\mathbf r$ in the epoch's body-fixed frame, use $h=\lVert\mathbf r\rVert-R_b$ and $\mathbf u_0=\mathbf r/\lVert\mathbf r\rVert$ instead. Its longitude changes as the integrator changes $\mathbf r$.

With captured raw angular velocity $\boldsymbol\omega$, advance the radial vector by Rodrigues rotation:

$$
\mathbf u(t)=\operatorname{Rot}\left(
\frac{\boldsymbol\omega}{\lVert\boldsymbol\omega\rVert},
\lVert\boldsymbol\omega\rVert\tau\right)\mathbf u_0.
$$

Zero spin leaves it unchanged. The captured spin uses the same relative-to-raw conversion as kOS `BODY:ANGULARVEL`; using KSP's unconverted relative vector would rotate about the wrong axes.

Let $k$ be `ScaledSpace.InverseScaleFactor` and $\mathbf d_s(t)$ the body-center-to-Sun vector in scaled-space length units. The solar direction at the query point is

$$
\mathbf s=\frac{\mathbf d_s(t)-k(R_b+h)\mathbf u(t)}
 {\lVert\mathbf d_s(t)-k(R_b+h)\mathbf u(t)\rVert}.
$$

Thus Sun geometry includes the query's altitude and its displacement from the body's center. The baseline $\mathbf d_s(t_0)$ preserves the inspected native wrapper's scaled-transform geometry; future orbital displacements are added to that baseline.

## 5. Delayed and normalized solar heating

Let $\mathbf a$ be the captured `bodyTransform.up` thermal axis. It is stored separately from the geographic basis to preserve the installed native calculation. Define the colatitude and Sun-axis angle

$$
\theta=\operatorname{acos}_{KSP}(\mathbf a\cdot\mathbf u),\qquad
\alpha=\operatorname{acos}_{KSP}(\mathbf a\cdot\mathbf s).
$$

Dot products use float components and float arithmetic, as in KSP's `Vector3.Dot`. If `acos` produces NaN from rounding beyond its domain, the native fallback is $\pi$ for a negative argument and zero otherwise.

Before folding latitude into an absolute value, compute the daily solar bounds

$$
q_{max}=\frac{1+\cos(\alpha-\theta)}2,\qquad
q_{min}=\frac{1+\cos(\alpha+\theta)}2,\qquad D=q_{max}-q_{min}.
$$

KSP applies a fixed 45° thermal lag, signed by the body's rotation period:

$$
\beta=\frac\pi4\operatorname{sign}(\text{rotationPeriod}),\qquad
q=\frac{1+\mathbf s\cdot\operatorname{Rot}(\mathbf a,\beta)\mathbf u}2.
$$

The actual implementation captures the Unity quaternion once and uses its managed float multiplication expression. The sign above follows `Mathf.Sign`, which returns +1 at zero. On a prograde rotating body the shifted radial vector represents a later local orientation, producing delayed heating rather than a maximum exactly at solar noon.

The solar factor entering the temperature offset is

$$
N=
\begin{cases}
(q-q_{min})/D, & D>0.001,\\
q_{min}+D/2, & D\leq0.001.
\end{cases}
$$

If the division branch returns NaN, use $N=1$ when $q>0.5$, otherwise $N=0$. There is no general clamp of $N$ to [0,1] in this branch. The small-range branch is important at the poles, where a normalized day/night amplitude would otherwise divide by zero or magnify rounding.

As a check, with zero solar declination at the equator, $q_{min}=0$, $q_{max}=1$, and $N=(1+\cos(\text{hour angle}+\beta))/2$, using hour angle measured along positive rotation. At a pole the range collapses and the guarded average remains finite.

The absolute thermal latitude for the curves is

$$
\Phi=\frac{180}{\pi}\left[\frac\pi2-\min(\theta,\pi-\theta)\right].
$$

Folding happens after computing the solar bounds. The latitude curves are north/south symmetric in their arguments, but this does not make the complete Sun geometry identical in both hemispheres.

## 6. Season, eccentricity and temperature composition

KSP selects the reference body's orbit with `GetBodyReferencing(body, sun)`: ascend the parent hierarchy until the selected body directly orbits the Sun. For a moon, this is normally its parent planet's solar orbit, not the moon's orbit around that planet.

Let $\nu$ be that orbit's true anomaly in radians. Its seasonal curve argument is

$$
\nu_d=\operatorname{wrap}_{[0,360)}(180\nu/\pi).
$$

Let $r_o$ be the same orbit's current radius, with periapsis $r_p$ and apoapsis $r_a$. For nonzero eccentricity,

$$
f_e=\frac{r_o-r_p}{r_a-r_p}.
$$

This runs from zero at periapsis to one at apoapsis. For an exactly circular orbit the eccentricity contribution is **zero**, rather than evaluating $C_e(0)$ or dividing by a zero radius span.

The complete offset is

$$
\boxed{\Delta T=B(\Phi)+L(\Phi)N+S(\nu_d)A(\Phi)
       +\begin{cases}C_e(f_e),&e\ne0,\\0,&e=0.\end{cases}}
$$

The seasonal product $S A$ is multiplied in float before conversion to double, matching the installed code. Finally, $T=T_0(h)+U(h)\Delta T$. The altitude multiplier scales **all four** contributions, not only the daily solar term. Its configured sign can change with altitude; a warmer offset therefore need not increase temperature in every layer.

“Season” here means an orbital-anomaly lookup configured by the planet pack, not a calendar or a physical atmospheric circulation simulation. Likewise, eccentricity heating is the configured distance-fraction curve, not an additional automatically calculated inverse-square heating law. Earth in the tested RSS configuration has a zero eccentricity bias curve.

## 7. Future-time orbital extension

Live KSP APIs cannot be used safely by the prediction workers. Capture instead copies elliptical orbit elements and orientation. For each relevant celestial parent-child link, with semimajor axis $a_o$, eccentricity $e$, period $\mathcal P$ and mean anomaly $M_0$ at capture,

$$
M(\tau)=M_0+\frac{2\pi}{\mathcal P}\tau,\qquad E-e\sin E=M.
$$

$E$ is eccentric anomaly. The implementation reduces $M$ to [-π,π] and solves Kepler's equation with bracketed Newton iteration, falling back to a bracket midpoint when a Newton step leaves the interval. With captured unit periapsis and transverse vectors $\mathbf p_o,\mathbf q_o$,

$$
\begin{aligned}
\mathbf r_o(\tau)&=a_o(\cos E-e)\mathbf p_o
                  +a_o\sqrt{1-e^2}\sin E\,\mathbf q_o,\\
r_o(\tau)&=a_o(1-e\cos E),\\
\nu(\tau)&=\operatorname{atan2}(\sqrt{1-e^2}\sin E,\cos E-e).
\end{aligned}
$$

The basis vectors are captured from KSP's positions at true anomaly zero and π/2, with its orbital `xzy` conversion into world axes. Capture checks the port against KSP's relative position at $t_0$ and $t_0+3600$ s; disagreement beyond $\max(0.01\text{ m},10^{-8}r_o)$ rejects the snapshot.

The future center-to-Sun vector is anchored to its captured baseline:

$$
\mathbf d_s(t)=\mathbf d_s(t_0)+k\sum_j\sigma_j
 [\mathbf r_j(\tau)-\mathbf r_j(0)].
$$

Sun ancestry links have $\sigma_j=+1$ and body ancestry links have $\sigma_j=-1$; shared links cancel. This includes a moon's motion when calculating its solar direction, while still using its planet's solar orbit for the seasonal term.

To preserve the native cached phase at capture, seasonal state advances by differences:

$$
\nu_{native}(t)=\nu_{native}(t_0)+[\nu_{managed}(\tau)-\nu_{managed}(0)],\qquad
f_e(t)=f_e(t_0)+\frac{r_{managed}(\tau)-r_{managed}(0)}{r_a-r_p}.
$$

The anomaly is wrapped only when forming its degree-valued curve argument. Circular orbits continue to omit the eccentricity term. Spin, orbital elements, curve keys and scalar configuration remain fixed over a snapshot's lifetime; snapshots must be refreshed when their configuration or starting frame changes. This propagation is not a model of changing orbital elements or atmospheric weather.

## 8. Boundaries and helper quantities

For an airless body or $h\geq H_a$, kOS-ATM returns $P=T=\rho=\Delta T=0$. Zero temperature is an API vacuum sentinel, not the physical background radiation temperature. Below sea level, the same curve/fallback branches apply; the addon rejects $h\leq-R_b$, nonfinite inputs and latitude outside [-90°,90°].

Within the atmosphere, density is zero if pressure or temperature is nonpositive. Nonfinite resulting gas properties or negative density are rejected. The configured analytic branches must therefore stay within a valid domain; the addon does not invent a replacement atmosphere for invalid settings.

The scale-height helper uses local ideal-gas and gravity values:

$$
H_{local}=\frac{\mathcal R T}{M_g g(h)}
         =\frac{\mathcal R T(R_b+h)^2}{M_g\mu},\qquad
g(h)=\frac\mu{(R_b+h)^2}.
$$

It is a hydrostatic characteristic length for guidance. Because the configured pressure curve is independent of the spatial temperature corrections, this quantity is not guaranteed to equal $-[d\ln\rho/dh]^{-1}$ or the actual pressure-curve gradient length.

The density-to-altitude helper numerically inverts the captured geographic column at $t_0$. It returns atmosphere depth for zero density and zero altitude for density at least the column's sea-level value. Otherwise it scans 128 intervals in [0,$H_a$], requires exactly one detected sign-change bracket, then bisects 48 times. This is a bounded column lookup, not an analytic global inverse; the finite scan is not a proof that an arbitrary nonmonotonic custom curve has no additional narrow or tangent roots.

## 9. Scope and evidence

This is ambient static gas temperature and density. Shock/external temperature, vessel/part heating, radiative body flux, wind and weather are separate quantities. The inspected native ambient offset is calculated before the `getBodyFlux` branch, so those flux calculations are unnecessary for this API. The port does not apply eclipse/raycast results to the offset, and should not be interpreted as a weather or full heat-transfer model.

The reconstruction used installed `Assembly-CSharp.dll` MVID `4b449f28-41f8-4227-adfa-ad3149c8fdba`, including `GetPressure`, `GetTemperature`, `GetAtmoThermalStats`, `GetFullTemperature`, `GetDensity` and the FlightIntegrator composition. The [threading audit](../KSP-AtmosphereResearch/docs/ThreadingAudit.md) records the native boundaries. In-game benchmark comparisons of the frozen managed kernel found a maximum temperature discrepancy of 0.0000611 K and relevant density discrepancy of 0.0000293% against native, with deterministic multiworker results. These are measured tolerances, not a claim of bit-for-bit equivalence for all configurations.

The model fails explicitly on unsupported weighted/looping curves, custom virtual thermal overrides, nonelliptical celestial orbits and atmospheres on the primary Sun. Runtime patches or weather mods can change live behavior without changing the copied fields; such installations need renewed comparison. Current-epoch physics is reconstructed and tested in RSS/RO/FAR. The future-time extension's full in-game parity and performance remain the outstanding validation step.
