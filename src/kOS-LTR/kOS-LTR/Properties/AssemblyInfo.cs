using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("kOS.Addons.LTR")]
[assembly: AssemblyDescription("Open-loop lifting trajectory predictor for kOS")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("")]
[assembly: AssemblyProduct("kOS.Addons.LTR")]
[assembly: AssemblyCopyright("")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]
[assembly: ComVisible(false)]
[assembly: Guid("5b1eb4c3-93d4-4e0f-8168-d7d8029411f7")]
[assembly: AssemblyVersion("1.0.1.0")]
[assembly: AssemblyFileVersion("1.0.1.0")]

// KSP uses these declarations to load kOS-LTR after the assemblies whose
// types are inspected by kOS' startup add-on walk.  Without them the DLL may
// appear in KSP.log while its [kOSAddon] type is still absent from ADDONS.
[assembly: KSPAssemblyDependency("kOS", 1, 1)]
[assembly: KSPAssemblyDependency("FerramAerospaceResearch", 0, 16)]
