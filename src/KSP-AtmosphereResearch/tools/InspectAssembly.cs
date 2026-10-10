using System;
using System.Text.RegularExpressions;
using Mono.Cecil;
class InspectAssembly
{
    static void Inspect(TypeDefinition t, Regex filter, Regex methods)
    {
        if (filter.IsMatch(t.FullName))
        {
            Console.WriteLine("TYPE " + t.FullName + " " + t.Attributes);
            foreach (var f in t.Fields) Console.WriteLine("FIELD " + f);
            foreach (var p in t.Properties) Console.WriteLine("PROPERTY " + p);
            foreach (var m in t.Methods)
            {
                Console.WriteLine("METHOD " + m + " " + m.Attributes);
                if (m.HasBody && methods.IsMatch(m.Name))
                {
                    foreach (var p in m.Parameters) Console.WriteLine("ARG " + p.Index + " " + p.Name);
                    foreach (var v in m.Body.Variables) Console.WriteLine("LOCAL " + v);
                    foreach (var i in m.Body.Instructions) Console.WriteLine(i);
                }
            }
        }
        foreach (var n in t.NestedTypes) Inspect(n, filter, methods);
    }
    static void Main(string[] args)
    {
        var filter = new Regex(args[1]);
        var methods = new Regex(args[2]);
        var a = AssemblyDefinition.ReadAssembly(args[0]);
        {
            Console.WriteLine("ASSEMBLY " + a.Name + " MVID " + a.MainModule.Mvid);
            foreach (var t in a.MainModule.Types) Inspect(t, filter, methods);
        }
    }
}
