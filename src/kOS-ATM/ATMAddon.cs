using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Exceptions;
using kOS.Suffixed;

namespace KOSAtmosphere
{
    [kOS.Safe.Utilities.KOSNomenclature("AtmosphereSnapshot")]
    public sealed class AtmosphereSnapshotValue : Structure
    {
        public AtmosphereSnapshot Model { get; private set; }
        public AtmosphereSnapshotValue(AtmosphereSnapshot model)
        {
            Model = model;
            AddSuffix("EPOCHUT", new Suffix<ScalarValue>(() => ScalarValue.Create(Model.EpochUT)));
            AddSuffix("BODYNAME", new Suffix<StringValue>(() => new StringValue(Model.BodyName)));
            AddSuffix("DEPTH", new Suffix<ScalarValue>(() => ScalarValue.Create(Model.AtmosphereDepth)));
            AddSuffix("GETAT", new OneArgsSuffix<Lexicon, Lexicon>(GetAt));
            AddSuffix("GETCOLUMN", new OneArgsSuffix<Lexicon, ScalarValue>(h => Sample(Model.EvaluateColumn(h.GetDoubleValue()))));
            AddSuffix("GETDENSITYAT", new OneArgsSuffix<ScalarValue, ScalarValue>(h => ScalarValue.Create(Model.EvaluateColumn(h.GetDoubleValue()).Density)));
            AddSuffix("GETALTFORDENSITY", new OneArgsSuffix<ScalarValue, ScalarValue>(rho => ScalarValue.Create(Model.AltitudeForDensity(rho.GetDoubleValue()))));
            AddSuffix("GETSCALEHEIGHTAT", new OneArgsSuffix<ScalarValue, ScalarValue>(h => ScalarValue.Create(Model.ScaleHeightColumn(h.GetDoubleValue()))));
        }
        private Lexicon GetAt(Lexicon args)
        {
            return Sample(Model.EvaluateGeographic(Number(args, "latitude"), Number(args, "longitude"), Number(args, "altitude"), OptionalNumber(args, "ut", Model.EpochUT)));
        }
        internal static double Number(Lexicon args, string key)
        {
            Structure value;
            if (args == null || !args.TryGetValue(new StringValue(key), out value) || !(value is ScalarValue)) throw new KOSException("Missing numeric atmosphere argument: " + key);
            double result = ((ScalarValue)value).GetDoubleValue();
            if (!AtmosphereVector.Finite(result)) throw new KOSException("Atmosphere argument must be finite: " + key);
            return result;
        }
        internal static double OptionalNumber(Lexicon args, string key, double fallback)
        {
            Structure value; return args != null && args.TryGetValue(new StringValue(key), out value) ? Number(args, key) : fallback;
        }
        public static Lexicon Sample(AtmosphereSample sample)
        {
            var result = new Lexicon();
            result.Add(new StringValue("pressure"), ScalarValue.Create(sample.PressurePa));
            result.Add(new StringValue("temperature"), ScalarValue.Create(sample.TemperatureK));
            result.Add(new StringValue("density"), ScalarValue.Create(sample.Density));
            result.Add(new StringValue("temperature_offset"), ScalarValue.Create(sample.TemperatureOffsetK));
            return result;
        }
        /// <summary>Resolve an explicitly supplied snapshot or capture on the main thread before Task.Run.</summary>
        public static AtmosphereSnapshot ForPrediction(Lexicon args, Vessel vessel, AtmosphereVector bodySpin)
        {
            Structure value; AtmosphereSnapshot model;
            if (args.TryGetValue(new StringValue("atmosphere"), out value))
            {
                var snapshot = value as AtmosphereSnapshotValue;
                if (snapshot == null) throw new KOSException("atmosphere must be ADDONS:ATM:SNAPSHOT()");
                model = snapshot.Model;
            }
            else model = AtmosphereCapture.Capture(vessel);
            if (model.BodyName != vessel.mainBody.bodyName) throw new KOSException("Atmosphere snapshot belongs to another body");
            if ((model.AngularVelocity - bodySpin).Length > 1e-9) throw new KOSException("Initialize predictor body spin before capturing the atmosphere snapshot");
            return model;
        }
    }
}
namespace kOS.AddOns.ATMAddon
{
    [kOSAddon("ATM")]
    [kOS.Safe.Utilities.KOSNomenclature("ATMAddon")]
    public sealed class Addon : Suffixed.Addon
    {
        public Addon(SharedObjects shared) : base(shared)
        {
            AddSuffix("SNAPSHOT", new NoArgsSuffix<KOSAtmosphere.AtmosphereSnapshotValue>(() => new KOSAtmosphere.AtmosphereSnapshotValue(KOSAtmosphere.AtmosphereCapture.Capture(shared.Vessel))));
            AddSuffix("SNAPSHOTBODY", new OneArgsSuffix<KOSAtmosphere.AtmosphereSnapshotValue, BodyTarget>(SnapshotBody));
            AddSuffix("GETAT", new OneArgsSuffix<Lexicon, Lexicon>(GetAt));
            AddSuffix("GETDENSITYAT", new OneArgsSuffix<ScalarValue, ScalarValue>(h => ScalarValue.Create(KOSAtmosphere.AtmosphereCapture.Capture(shared.Vessel).EvaluateColumn(h.GetDoubleValue()).Density)));
            AddSuffix("GETALTFORDENSITY", new OneArgsSuffix<ScalarValue, ScalarValue>(rho => ScalarValue.Create(KOSAtmosphere.AtmosphereCapture.Capture(shared.Vessel).AltitudeForDensity(rho.GetDoubleValue()))));
            AddSuffix("GETSCALEHEIGHTAT", new OneArgsSuffix<ScalarValue, ScalarValue>(h => ScalarValue.Create(KOSAtmosphere.AtmosphereCapture.Capture(shared.Vessel).ScaleHeightColumn(h.GetDoubleValue()))));
            AddSuffix("DENSITY", new Suffix<ScalarValue>(() => ScalarValue.Create(shared.Vessel.atmDensity)));
            AddSuffix("TEMPERATURE", new Suffix<ScalarValue>(() => ScalarValue.Create(shared.Vessel.atmosphericTemperature)));
            AddSuffix("PRESSURE", new Suffix<ScalarValue>(() => ScalarValue.Create(shared.Vessel.staticPressurekPa * 1000)));
        }
        private KOSAtmosphere.AtmosphereSnapshotValue SnapshotBody(BodyTarget target)
        {
            CelestialBody body = target.Body;
            return new KOSAtmosphere.AtmosphereSnapshotValue(KOSAtmosphere.AtmosphereCapture.Capture(body));
        }
        private Lexicon GetAt(Lexicon args)
        {
            Structure value; CelestialBody body = shared.Vessel.mainBody;
            if (args.TryGetValue(new StringValue("body"), out value))
            {
                var target = value as BodyTarget; if (target == null) throw new KOSException("body must be a kOS celestial body"); body = target.Body;
            }
            double lat = KOSAtmosphere.AtmosphereSnapshotValue.Number(args, "latitude"), lon = KOSAtmosphere.AtmosphereSnapshotValue.Number(args, "longitude"), h = KOSAtmosphere.AtmosphereSnapshotValue.Number(args, "altitude");
            var snapshot = KOSAtmosphere.AtmosphereCapture.Capture(body);
            return KOSAtmosphere.AtmosphereSnapshotValue.Sample(snapshot.EvaluateGeographic(lat, lon, h, KOSAtmosphere.AtmosphereSnapshotValue.OptionalNumber(args, "ut", snapshot.EpochUT)));
        }
        public override BooleanValue Available() { return true; }
    }
}
