using System;
using System.Reflection;

namespace KSPAtmosphereResearch
{
    internal static class ReflectionApi
    {
        public const BindingFlags AnyInstance = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        public static Type FindType(string name)
        {
            foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type found = assembly.GetType(name, false);
                if (found != null) return found;
            }
            return null;
        }
        public static MethodInfo Method(Type type, string name, BindingFlags flags, params Type[] args)
        {
            MethodInfo result = type.GetMethod(name, flags, null, args, null);
            if (result == null) throw new MissingMethodException(type.FullName, name);
            return result;
        }
        public static double Number(object value, string field)
        { return Convert.ToDouble(value.GetType().GetField(field, AnyInstance).GetValue(value)); }
    }

    /// <summary>Optional loaded-mod adapters. No mod DLL is loaded or distributed by this assembly.</summary>
    public sealed class ModCandidate : IAtmosphereCandidate
    {
        private readonly string kind;
        private readonly Type apiType;
        private readonly MethodInfo method, densityMethod, pressureMethod, setupMethod;
        private object simulation;
        private CelestialBody contextBody;
        private readonly string bindError;
        public string Id { get { return kind; } }
        public string Description { get { return kind == "mechjeb_private_diagnostic" ? "Installed private reentry methods on an isolated context; research only" : "Installed public mod atmosphere API via reflection"; } }
        public ModCandidate(string candidateId)
        {
            kind = candidateId;
            try
            {
                if (kind == "far_registered")
                {
                    apiType = ReflectionApi.FindType("FerramAerospaceResearch.FARAtmosphere");
                    if (apiType != null) method = ReflectionApi.Method(apiType, "GetGasProperties", BindingFlags.Public | BindingFlags.Static,
                        typeof(CelestialBody), typeof(Vector3d), typeof(double));
                }
                else if (kind == "trajectories_position")
                {
                    apiType = ReflectionApi.FindType("Trajectories.StockAeroUtil");
                    if (apiType != null)
                    {
                        method = ReflectionApi.Method(apiType, "GetTemperature", BindingFlags.Public | BindingFlags.Static, typeof(Vector3d), typeof(CelestialBody));
                        densityMethod = ReflectionApi.Method(apiType, "GetDensity", BindingFlags.Public | BindingFlags.Static, typeof(Vector3d), typeof(CelestialBody));
                    }
                }
                else if (kind == "mechjeb_private_diagnostic")
                {
                    apiType = ReflectionApi.FindType("MuMech.ReentrySimulation");
                    if (apiType != null)
                    {
                        method = ReflectionApi.Method(apiType, "GetTemperature", ReflectionApi.AnyInstance, typeof(Vector3d), typeof(double));
                        pressureMethod = ReflectionApi.Method(apiType, "StaticPressure", ReflectionApi.AnyInstance, typeof(double));
                        densityMethod = ReflectionApi.Method(apiType, "AirDensity", ReflectionApi.AnyInstance, typeof(Vector3d), typeof(double));
                        Type curvesType = apiType.GetNestedType("SimCurves", BindingFlags.Public);
                        setupMethod = ReflectionApi.Method(curvesType, "Setup", ReflectionApi.AnyInstance, typeof(CelestialBody));
                    }
                }
                else throw new ArgumentException("Unknown candidate", "candidateId");
            }
            catch (Exception exception) { bindError = exception.GetType().Name + ": " + exception.Message; }
        }
        public void Dispose() { simulation = null; contextBody = null; }
        public AtmosphereSample Sample(AtmosphereQuery query)
        {
            if (bindError != null) return AtmosphereSample.Failure("unavailable", bindError);
            if (apiType == null || method == null) return AtmosphereSample.Failure("unavailable", "Mod or expected API is not loaded");
            if (kind == "far_registered")
            {
                // FAR uses (latitude degrees, longitude degrees, altitude metres), NOT a world position.
                object gas = method.Invoke(null, new object[] { query.Body,
                    new Vector3d(query.LatitudeDegrees, query.LongitudeDegrees, query.AltitudeMeters), query.UniversalTime });
                PropertyInfo custom = apiType.GetProperty("IsCustom", BindingFlags.Public | BindingFlags.Static);
                return AtmosphereSample.Values(query, ReflectionApi.Number(gas, "Pressure"), ReflectionApi.Number(gas, "Temperature"),
                    ReflectionApi.Number(gas, "Density"), double.NaN, "IsCustom=" + (custom == null ? "unknown" : custom.GetValue(null, null).ToString()));
            }
            if (kind == "trajectories_position")
            {
                object[] args = { query.WorldPosition, query.Body };
                return AtmosphereSample.Values(query, query.Body.GetPressure(query.AltitudeMeters) * 1000,
                    (double)method.Invoke(null, args), (double)densityMethod.Invoke(null, args), double.NaN,
                    "Pressure supplied by body.GetPressure; temperature/density are direct mod outputs");
            }
            if (contextBody != query.Body)
            {
                // Never mutate the active MechJeb predictor, use its pool, or start a simulation.
                object newSimulation = Activator.CreateInstance(apiType);
                Type curvesType = apiType.GetNestedType("SimCurves", BindingFlags.Public);
                object newCurves = Activator.CreateInstance(curvesType, true);
                setupMethod.Invoke(newCurves, new object[] { query.Body });
                apiType.GetField("_mainBody", ReflectionApi.AnyInstance).SetValue(newSimulation, query.Body);
                apiType.GetField("_simCurves", ReflectionApi.AnyInstance).SetValue(newSimulation, newCurves);
                apiType.GetField("_bodyRadius", ReflectionApi.AnyInstance).SetValue(newSimulation, query.Body.Radius);
                simulation = newSimulation; contextBody = query.Body;
            }
            Vector3d bodyRelativePosition = query.WorldPosition - query.Body.position;
            object[] positionArgs = { bodyRelativePosition, query.AltitudeMeters };
            return AtmosphereSample.Values(query, (double)pressureMethod.Invoke(simulation, new object[] { query.AltitudeMeters }) * 1000,
                (double)method.Invoke(simulation, positionArgs), (double)densityMethod.Invoke(simulation, positionArgs), double.NaN,
                "Private installed methods, current ephemeris only");
        }
    }
}
