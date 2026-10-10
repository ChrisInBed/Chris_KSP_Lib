using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using UnityEngine;

namespace KSPAtmosphereResearch
{
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public sealed class FlightRecorder : MonoBehaviour
    {
        private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;
        private readonly List<IAtmosphereCandidate> candidates = new List<IAtmosphereCandidate>();
        private readonly HashSet<string> recordedBodies = new HashSet<string>();
        private StreamWriter csv;
        private string sessionDirectory;
        private double interval = 0.5, probeInterval = 30, nextSample, nextProbe;
        private bool includeProbes = true;
        private long sampleId, physicsTick;
        private bool stopped;
        private readonly Dictionary<string, FieldInfo> integratorFields = new Dictionary<string, FieldInfo>();

        private void Start()
        {
            try
            {
                ConfigNode config = GameDatabase.Instance.GetConfigNode("KSP_ATMOSPHERE_RESEARCH");
                if (config != null)
                {
                    bool configEnabled;
                    if (bool.TryParse(config.GetValue("enabled"), out configEnabled) && !configEnabled) { enabled = false; return; }
                    interval = ReadInterval(config, "sampleIntervalRealSeconds", interval, 0.1);
                    probeInterval = ReadInterval(config, "probeIntervalRealSeconds", probeInterval, 5);
                    bool probes;
                    if (bool.TryParse(config.GetValue("includeProbes"), out probes)) includeProbes = probes;
                }
                candidates.Add(new StockCandidate(true));
                candidates.Add(new StockCandidate(false));
                candidates.Add(new StockCandidate(false, true));
                candidates.Add(new ModCandidate("far_registered"));
                candidates.Add(new ModCandidate("trajectories_position"));
                candidates.Add(new ModCandidate("mechjeb_private_diagnostic"));
                foreach (string name in new[] { "altitude", "atmosphericTemperature", "staticPressurekPa", "density", "atmosphereTemperatureOffset", "sunDot" })
                    integratorFields[name] = typeof(FlightIntegrator).GetField(name, ReflectionApi.AnyInstance);
                string logRoot = Path.Combine(KSPUtil.ApplicationRootPath, "Logs", "AtmosphereResearch");
                sessionDirectory = Path.Combine(logRoot, DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ", Invariant) + "_" + Guid.NewGuid().ToString("N").Substring(0, 8));
                Directory.CreateDirectory(sessionDirectory);
                WriteEnvironment();
                csv = new StreamWriter(Path.Combine(sessionDirectory, "samples.csv"), false, new UTF8Encoding(false));
                csv.WriteLine("schema_version,sample_id,physics_tick,record_kind,probe_id,ut_s,realtime_s,vessel_id,vessel_name,body,situation,warp_rate,latitude_deg,longitude_deg,altitude_m,in_atmosphere,sun_height_deg,sun_axial_dot,direct_sunlight,reference_coherent,reference_pressure_pa,reference_temperature_k,reference_density_kg_m3,external_temperature_k,fi_altitude_m,fi_pressure_pa,fi_temperature_k,fi_density_kg_m3,fi_offset_k,fi_sun_dot,root_part_density_kg_m3,min_part_density_kg_m3,max_part_density_kg_m3,candidate,status,pressure_pa,temperature_k,density_kg_m3,offset_k,pressure_error_pa,temperature_error_k,density_error_kg_m3,density_relative_error,detail");
                csv.Flush();
                Debug.Log("[AtmosphereResearch] Logging to " + sessionDirectory);
                ScreenMessages.PostScreenMessage("Atmosphere research logger started (Logs/AtmosphereResearch)", 8f, ScreenMessageStyle.UPPER_CENTER);
                StartCoroutine(RecordAfterPhysics());
            }
            catch (Exception exception) { StopWithError(exception); }
        }
        private static double ReadInterval(ConfigNode config, string key, double fallback, double minimum)
        {
            double parsed;
            return double.TryParse(config.GetValue(key), NumberStyles.Float, Invariant, out parsed)
                && AtmosphereQuery.Finite(parsed) && parsed >= minimum ? parsed : fallback;
        }
        private IEnumerator RecordAfterPhysics()
        {
            while (!stopped)
            {
                yield return new WaitForFixedUpdate();
                ++physicsTick;
                if (NativeBenchmark.Active) continue;
                double now = Time.realtimeSinceStartup;
                if (now < nextSample) continue;
                nextSample = now + interval;
                Vessel vessel = FlightGlobals.ActiveVessel;
                if (!FlightGlobals.ready || vessel == null || !vessel.loaded || vessel.packed || vessel.mainBody == null) continue;
                try
                {
                    Capture(vessel, now);
                    csv.Flush();
                }
                catch (Exception exception) { StopWithError(exception); }
            }
        }
        private double IntegratorNumber(FlightIntegrator integrator, string name)
        {
            FieldInfo field = integratorFields[name];
            return integrator == null || field == null ? double.NaN : Convert.ToDouble(field.GetValue(integrator), Invariant);
        }
        private sealed class ReferenceReading
        {
            public double Pressure, Temperature, Density, External, FiAltitude, FiPressure, FiTemperature, FiDensity, FiOffset, FiSunDot, RootDensity, MinPartDensity, MaxPartDensity;
            public bool Coherent;
        }
        private void Capture(Vessel vessel, double realtime)
        {
            CelestialBody body = vessel.mainBody;
            if (recordedBodies.Add(body.name)) WriteBody(body);
            AtmosphereQuery query = new AtmosphereQuery(body, vessel.latitude, vessel.longitude, vessel.altitude);
            FlightIntegrator integrator = vessel.GetComponent<FlightIntegrator>();
            ReferenceReading reference = new ReferenceReading
            {
                Pressure = vessel.staticPressurekPa * 1000,
                Temperature = vessel.atmosphericTemperature,
                Density = vessel.atmDensity,
                External = vessel.externalTemperature,
                FiAltitude = IntegratorNumber(integrator, "altitude"),
                FiPressure = IntegratorNumber(integrator, "staticPressurekPa") * 1000,
                FiTemperature = IntegratorNumber(integrator, "atmosphericTemperature"),
                FiDensity = IntegratorNumber(integrator, "density"),
                FiOffset = IntegratorNumber(integrator, "atmosphereTemperatureOffset"),
                FiSunDot = IntegratorNumber(integrator, "sunDot")
            };
            reference.RootDensity = vessel.rootPart == null ? double.NaN : vessel.rootPart.atmDensity;
            reference.MinPartDensity = double.PositiveInfinity;
            reference.MaxPartDensity = double.NegativeInfinity;
            foreach (Part part in vessel.parts)
            {
                reference.MinPartDensity = Math.Min(reference.MinPartDensity, part.atmDensity);
                reference.MaxPartDensity = Math.Max(reference.MaxPartDensity, part.atmDensity);
            }
            reference.Coherent = Close(reference.Pressure, reference.FiPressure) && Close(reference.Temperature, reference.FiTemperature)
                && Close(reference.Density, reference.FiDensity) && Math.Abs(query.AltitudeMeters - reference.FiAltitude) <= 1;
            ++sampleId;
            RecordLocation(vessel, query, reference, realtime, "vehicle", "vehicle");
            if (!includeProbes || realtime < nextProbe || !body.atmosphere) return;
            nextProbe = realtime + probeInterval;
            RecordLocation(vessel, new AtmosphereQuery(body, query.LatitudeDegrees, query.LongitudeDegrees + 90, query.AltitudeMeters), null, realtime, "probe", "longitude_plus_90");
            RecordLocation(vessel, new AtmosphereQuery(body, query.LatitudeDegrees, query.LongitudeDegrees + 180, query.AltitudeMeters), null, realtime, "probe", "longitude_plus_180");
            RecordLocation(vessel, new AtmosphereQuery(body, -query.LatitudeDegrees, query.LongitudeDegrees, query.AltitudeMeters), null, realtime, "probe", "opposite_latitude");
            RecordLocation(vessel, new AtmosphereQuery(body, 90, query.LongitudeDegrees, query.AltitudeMeters), null, realtime, "probe", "north_pole");
            RecordLocation(vessel, new AtmosphereQuery(body, -90, query.LongitudeDegrees, query.AltitudeMeters), null, realtime, "probe", "south_pole");
            foreach (double height in new[] { -100.0, 0.0, body.atmosphereDepth - 1, body.atmosphereDepth, body.atmosphereDepth + 1 })
                RecordLocation(vessel, new AtmosphereQuery(body, query.LatitudeDegrees, query.LongitudeDegrees, height), null, realtime, "probe", "altitude_" + height.ToString("R", Invariant));
        }
        private static bool Close(double left, double right)
        {
            return AtmosphereQuery.Finite(left) && AtmosphereQuery.Finite(right)
                && Math.Abs(left - right) <= 1e-8 + 1e-6 * Math.Max(Math.Abs(left), Math.Abs(right));
        }
        private void RecordLocation(Vessel vessel, AtmosphereQuery query, ReferenceReading reference, double realtime, string kind, string probe)
        {
            Vector3d ray = (Planetarium.fetch.Sun.position - query.WorldPosition).normalized;
            Vector3d upAxis = FlightGlobals.getUpAxis(query.Body, query.WorldPosition);
            double height = Math.Asin(Math.Max(-1, Math.Min(1, Vector3d.Dot(ray, upAxis)))) * 180 / Math.PI;
            double axial = Vector3d.Dot(ray, query.Body.bodyTransform.up);
            foreach (IAtmosphereCandidate candidate in candidates)
            {
                AtmosphereSample value;
                try { value = candidate.Sample(query); }
                catch (Exception exception)
                {
                    Exception cause = exception is TargetInvocationException && exception.InnerException != null ? exception.InnerException : exception;
                    value = AtmosphereSample.Failure("error", cause.GetType().Name + ": " + cause.Message);
                }
                bool comparable = reference != null;
                WriteCsv(new object[] { 1, sampleId, physicsTick, kind, probe, query.UniversalTime, realtime,
                    vessel.id, vessel.vesselName, query.Body.name, vessel.situation, TimeWarp.CurrentRate,
                    query.LatitudeDegrees, query.LongitudeDegrees, query.AltitudeMeters, query.InAtmosphere, height, axial,
                    comparable ? (object)vessel.directSunlight : null, comparable ? (object)reference.Coherent : null,
                    comparable ? (object)reference.Pressure : null, comparable ? (object)reference.Temperature : null,
                    comparable ? (object)reference.Density : null, comparable ? (object)reference.External : null,
                    comparable ? (object)reference.FiAltitude : null, comparable ? (object)reference.FiPressure : null,
                    comparable ? (object)reference.FiTemperature : null, comparable ? (object)reference.FiDensity : null,
                    comparable ? (object)reference.FiOffset : null, comparable ? (object)reference.FiSunDot : null,
                    comparable ? (object)reference.RootDensity : null, comparable ? (object)reference.MinPartDensity : null,
                    comparable ? (object)reference.MaxPartDensity : null, candidate.Id, value.Status, value.PressurePa, value.TemperatureK, value.DensityKgM3, value.TemperatureOffsetK,
                    comparable ? (object)(value.PressurePa - reference.Pressure) : null,
                    comparable ? (object)(value.TemperatureK - reference.Temperature) : null,
                    comparable ? (object)(value.DensityKgM3 - reference.Density) : null,
                    comparable && reference.Density > 1e-12 ? (object)((value.DensityKgM3 - reference.Density) / reference.Density) : null,
                    value.Detail });
            }
        }
        private void WriteCsv(object[] fields)
        {
            string[] cells = new string[fields.Length];
            for (int i = 0; i < fields.Length; ++i)
            {
                string text = fields[i] == null ? "" : fields[i] is double ? ((double)fields[i]).ToString("R", Invariant) : Convert.ToString(fields[i], Invariant);
                cells[i] = text.IndexOfAny(new[] { ',', '"', '\r', '\n' }) < 0 ? text : "\"" + text.Replace("\"", "\"\"") + "\"";
            }
            csv.WriteLine(string.Join(",", cells));
        }
        private void WriteEnvironment()
        {
            using (StreamWriter output = new StreamWriter(Path.Combine(sessionDirectory, "environment.txt")))
            {
                output.WriteLine("UTC: " + DateTime.UtcNow.ToString("O", Invariant));
                output.WriteLine("KSP: " + Versioning.GetVersionString());
                output.WriteLine("Unity: " + Application.unityVersion);
                output.WriteLine("Sampling: after WaitForFixedUpdate; real seconds=" + interval.ToString("R", Invariant));
                output.WriteLine("Reference: Vessel.staticPressurekPa, atmosphericTemperature, atmDensity; FlightIntegrator cross-check");
                foreach (IAtmosphereCandidate candidate in candidates) output.WriteLine("Candidate: " + candidate.Id + " | " + candidate.Description);
                foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
                    output.WriteLine("Assembly: " + assembly.FullName + " | MVID=" + assembly.ManifestModule.ModuleVersionId);
            }
        }
        private void WriteBody(CelestialBody body)
        {
            ConfigNode snapshot = new ConfigNode("ATMOSPHERE_BODY_SNAPSHOT");
            snapshot.AddValue("name", body.name);
            snapshot.AddValue("runtimeType", body.GetType().AssemblyQualifiedName);
            snapshot.AddValue("ut", Planetarium.GetUniversalTime().ToString("R", Invariant));
            snapshot.AddValue("idealGasConstant", PhysicsGlobals.IdealGasConstant.ToString("R", Invariant));
            foreach (FieldInfo field in typeof(CelestialBody).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (field.Name.IndexOf("atmosphere", StringComparison.OrdinalIgnoreCase) < 0
                    && field.Name.IndexOf("Temperature", StringComparison.OrdinalIgnoreCase) < 0
                    && field.Name != "Radius" && field.Name != "rotationPeriod") continue;
                object value = field.GetValue(body);
                FloatCurve curve = value as FloatCurve;
                if (curve != null)
                {
                    ConfigNode curveNode = snapshot.AddNode(field.Name);
                    foreach (Keyframe key in curve.Curve.keys)
                        curveNode.AddValue("key", key.time.ToString("R", Invariant) + " " + key.value.ToString("R", Invariant)
                            + " " + key.inTangent.ToString("R", Invariant) + " " + key.outTangent.ToString("R", Invariant));
                }
                else if (value != null && (field.FieldType.IsPrimitive || field.FieldType == typeof(string)))
                    snapshot.AddValue(field.Name, Convert.ToString(value, Invariant));
            }
            string fileName = body.flightGlobalsIndex.ToString(Invariant) + "_body.cfg";
            snapshot.Save(Path.Combine(sessionDirectory, fileName));
        }
        private void StopWithError(Exception exception)
        {
            Debug.LogError("[AtmosphereResearch] Recorder stopped: " + exception);
            stopped = true;
            Close();
        }
        private void OnDestroy() { stopped = true; Close(); }
        private void Close()
        {
            if (csv != null) { csv.Dispose(); csv = null; }
            foreach (IAtmosphereCandidate candidate in candidates) candidate.Dispose();
        }
    }
}
