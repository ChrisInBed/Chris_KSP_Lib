using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("kOS.Addons.GFOLD")]
[assembly: AssemblyDescription("GFOLD powered-descent trajectory planner for kOS")]
[assembly: AssemblyProduct("kOS-GFOLD")]
[assembly: ComVisible(false)]
[assembly: Guid("a9fe1170-f2ab-41bb-a723-b5306f38ae03")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]
[assembly: KSPAssemblyDependency("kOS", 1, 1)]

// MechJeb's alglib.dll is an ordinary CLR assembly (Version=1.0.0.0) and does
// not declare KSPAssemblyAttribute. KSPAssemblyDependency only matches
// assemblies registered through that attribute, so declaring "alglib" here
// makes KSP reject this addon even when the correct DLL is installed. The
// alglib reference in kOS-GFOLD.csproj retains the actual CLR dependency.
