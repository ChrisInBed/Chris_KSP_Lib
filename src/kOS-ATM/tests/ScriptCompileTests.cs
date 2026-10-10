using System;
using System.IO;
using kOS.Safe.Compilation;
using kOS.Safe.Compilation.KS;
using kOS.Safe.Persistence;

internal static class ScriptCompileTests
{
    private static void Main(string[] args)
    {
        string root=args[0];
        foreach(string relative in new[] {"uentry.ks","lib/atm_utils.ks","lib/edllib/uentry_core.ks","lib/edllib/gui_utils.ks","Falcon9_lib/f9utility.ks","boot/atm_check.ks"})
        {
            string code=File.ReadAllText(Path.Combine(root,"Script",relative));
            var options=new CompilerOptions {AllowClobberBuiltins=false,IsCalledFromRun=true,LoadProgramsInSameAddressSpace=true};
            var parts=new KSScript().Compile(GlobalPath.FromString("0:/"+relative),1,code,"compile-check",options);
            Console.WriteLine("kOS compiler passed: "+relative+" ("+parts.Count+" code parts)");
        }
    }
}
