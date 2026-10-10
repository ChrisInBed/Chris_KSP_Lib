using System;
using UnityEngine;

namespace KSPAtmosphereResearch
{
    /// <summary>A body-fixed location evaluated using the game's CURRENT ephemeris. Main thread only.</summary>
    public sealed class AtmosphereQuery
    {
        public readonly CelestialBody Body;
        public readonly double LatitudeDegrees, LongitudeDegrees, AltitudeMeters, UniversalTime;
        public readonly Vector3d WorldPosition;
        public bool InAtmosphere { get { return Body.atmosphere && AltitudeMeters < Body.atmosphereDepth; } }

        public AtmosphereQuery(CelestialBody body, double latitudeDegrees, double longitudeDegrees, double altitudeMeters)
        {
            if (body == null) throw new ArgumentNullException("body");
            if (!Finite(latitudeDegrees) || latitudeDegrees < -90 || latitudeDegrees > 90)
                throw new ArgumentOutOfRangeException("latitudeDegrees");
            if (!Finite(longitudeDegrees)) throw new ArgumentOutOfRangeException("longitudeDegrees");
            if (!Finite(altitudeMeters) || altitudeMeters <= -body.Radius)
                throw new ArgumentOutOfRangeException("altitudeMeters");
            Body = body;
            LatitudeDegrees = latitudeDegrees;
            LongitudeDegrees = ((longitudeDegrees + 180) % 360 + 360) % 360 - 180;
            AltitudeMeters = altitudeMeters;
            UniversalTime = Planetarium.GetUniversalTime();
            WorldPosition = body.GetWorldSurfacePosition(LatitudeDegrees, LongitudeDegrees, AltitudeMeters);
        }
        public static bool Finite(double value) { return !double.IsNaN(value) && !double.IsInfinity(value); }
    }

    public sealed class AtmosphereSample
    {
        public readonly double PressurePa, TemperatureK, DensityKgM3, TemperatureOffsetK;
        public readonly string Status, Detail;
        private AtmosphereSample(double pressure, double temperature, double density, double offset, string status, string detail)
        {
            PressurePa = pressure; TemperatureK = temperature; DensityKgM3 = density;
            TemperatureOffsetK = offset; Status = status; Detail = detail;
        }
        public static AtmosphereSample Values(AtmosphereQuery query, double pressurePa, double temperatureK,
            double densityKgM3, double offsetK = double.NaN, string detail = "")
        {
            bool valid = AtmosphereQuery.Finite(pressurePa) && AtmosphereQuery.Finite(temperatureK)
                && AtmosphereQuery.Finite(densityKgM3) && pressurePa >= 0 && densityKgM3 >= 0
                && (temperatureK > 0 || (pressurePa == 0 && densityKgM3 == 0));
            return new AtmosphereSample(pressurePa, temperatureK, densityKgM3, offsetK,
                valid ? (query.InAtmosphere ? "ok" : "vacuum") : "invalid", detail);
        }
        public static AtmosphereSample Failure(string status, string detail)
        { return new AtmosphereSample(double.NaN, double.NaN, double.NaN, double.NaN, status, detail); }
    }

    public interface IAtmosphereCandidate : IDisposable
    {
        string Id { get; }
        string Description { get; }
        AtmosphereSample Sample(AtmosphereQuery query);
    }

    public sealed class StockCandidate : IAtmosphereCandidate
    {
        private readonly bool thermal;
        private readonly bool flightGlobals;
        public string Id { get { return thermal ? "stock_thermal_now" : flightGlobals ? "flightglobals_position_baseline" : "body_altitude_baseline"; } }
        public string Description { get { return thermal ? "Native thermal offset plus altitude/offset full-temperature overload" : "Altitude-only negative control"; } }
        public StockCandidate(bool useThermal, bool useFlightGlobals = false) { thermal = useThermal; flightGlobals = useFlightGlobals; }
        public void Dispose() { }
        public AtmosphereSample Sample(AtmosphereQuery query)
        {
            CelestialBody body = query.Body;
            double pressure = flightGlobals ? FlightGlobals.getStaticPressure(query.WorldPosition, body) : body.GetPressure(query.AltitudeMeters);
            double offset = double.NaN;
            double temperature;
            if (thermal && query.InAtmosphere)
            {
                CelestialBody sun = Planetarium.fetch.Sun;
                if (sun == null || sun.scaledBody == null) throw new InvalidOperationException("Sun/scaled space not ready");
                // Match FlightIntegrator's scaled-space direction and float precision.
                Vector3d ray = (Vector3d)sun.scaledBody.transform.position - ScaledSpace.LocalToScaledSpace(query.WorldPosition);
                Vector3d upAxis = FlightGlobals.getUpAxis(body, query.WorldPosition);
                Vector3 sunDirection = (Vector3)(ray / Math.Max(ray.magnitude, double.Epsilon));
                double unusedEmissive, unusedAlbedo;
                body.GetAtmoThermalStats(false, sun, sunDirection, Vector3d.Dot(sunDirection, upAxis), upAxis,
                    query.AltitudeMeters, out offset, out unusedEmissive, out unusedAlbedo);
                temperature = body.GetFullTemperature(query.AltitudeMeters, offset);
            }
            else temperature = flightGlobals ? FlightGlobals.getExternalTemperature(query.WorldPosition, body) : body.GetTemperature(query.AltitudeMeters);
            double density = FlightGlobals.getAtmDensity(pressure, temperature, body);
            return AtmosphereSample.Values(query, pressure * 1000, temperature, density, offset);
        }
    }

    public static class AtmosphereApi
    {
        /// <summary>Selected current-ephemeris native model. MAIN THREAD ONLY. Pressure Pa, temperature K, density kg/m^3.</summary>
        public static AtmosphereSample SampleStockNow(CelestialBody body, double latitudeDegrees, double longitudeDegrees, double altitudeMeters)
        { return new StockCandidate(true).Sample(new AtmosphereQuery(body, latitudeDegrees, longitudeDegrees, altitudeMeters)); }
    }
}
