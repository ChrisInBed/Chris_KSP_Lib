using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using KOSGFOLD.Core;

namespace KOSGFOLD.Cli
{
    internal static class Program
    {
        private const int InvalidInput = 64, InternalError = 70;
        private static int Main(string[] args)
        {
            try
            {
                if (args.Length == 1 && args[0] == "selftest") { CoreDiagnostics.Run(); Console.Out.WriteLine("{\"ok\":true,\"status\":\"SELFTEST_PASSED\"}"); return 0; }
                if (args.Length < 3 || (args[0] != "solve" && args[0] != "sequence")) return Usage(); string input = null, output = null;
                for (int i = 1; i < args.Length; ++i) { if (args[i] == "--input" && i + 1 < args.Length) input = args[++i]; else if (args[i] == "--output" && i + 1 < args.Length) output = args[++i]; else return Usage(); }
                if (string.IsNullOrEmpty(input)) return Usage(); JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 256 }; object root = json.DeserializeObject(File.ReadAllText(input, Encoding.UTF8)); Planner planner = new Planner(); object result; bool ok;
                if (args[0] == "solve") { PlannerResult r = planner.Initialize(JsonAdapter.ParseInitialize(JsonAdapter.Object(root))); result = JsonAdapter.Result(r); ok = r.Ok; }
                else { Dictionary<string, object> doc = JsonAdapter.Object(root); PlannerResult initial = planner.Initialize(JsonAdapter.ParseInitialize(JsonAdapter.Object(JsonAdapter.Required(doc, "initialize")))); List<object> updatesOut = new List<object>(); PlannerResult previous = initial; ok = initial.Ok; if (ok && doc.ContainsKey("updates")) foreach (object value in JsonAdapter.Array(doc["updates"])) { UpdateRequest update = JsonAdapter.ParseUpdate(JsonAdapter.Object(value), previous); PlannerResult r = planner.Update(update); updatesOut.Add(JsonAdapter.Result(r)); previous = r; if (!r.Ok) { ok = false; break; } } result = new Dictionary<string, object> { { "ok", ok }, { "initialize", JsonAdapter.Result(initial) }, { "updates", updatesOut } }; }
                string text = json.Serialize(result); if (output == null) Console.Out.WriteLine(text); else File.WriteAllText(output, text, new UTF8Encoding(false)); return ok ? 0 : 2;
            }
            catch (ArgumentException ex) { Console.Error.WriteLine("Input error: " + ex.Message); return InvalidInput; }
            catch (Exception ex) { Console.Error.WriteLine(ex); return InternalError; }
        }
        private static int Usage() { Console.Error.WriteLine("Usage: kOS-GFOLD.Cli.exe selftest | (solve|sequence) --input FILE [--output FILE]"); return InvalidInput; }
    }
}
