# Building a distribution

From a Git checkout, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build-release.ps1 -Version 1.0.5
```

The version is an explicit package label; choose it when preparing the release. The script does not change assembly versions, commit, tag, install into KSP, or publish a release. Finalize the draft entries in `Changelog.md` and `更新日志.md` before distributing.

Requirements: Windows PowerShell 5.1 or newer, Git, a .NET SDK with Roslyn, .NET Framework 4.8 reference assemblies, Python for integration checks, and a KSP installation containing kOS, FAR and KSPBurst. The default KSP path matches the existing addon build script. For another installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build-release.ps1 -Version 1.0.5 `
    -KspRoot 'D:\Games\Kerbal Space Program' -OutputRoot '.\dist'
```

Use `-ReferenceRoot` to supply a directory containing `Unity.Mathematics.dll`, `FerramAerospaceResearch.dll`, and `FerramAerospaceResearch.Base.dll`; otherwise they are read from installed GameData. These references are never bundled.

The script calls `src/kOS-ATM/build.ps1 -RunTests` to compile all three addons and run managed atmosphere tests, predictor tests, kOS compilation checks and integration checks. It then creates:

- `dist/Chris_GNC_Suite-v<VERSION>/`: unpacked distribution.
- `dist/Chris_GNC_Suite-v<VERSION>.zip`: ZIP containing the versioned distribution folder, with `Ships`, `GameData`, `docs`, `crafts`, readmes, changelogs, license and installation instructions inside it, matching the v1.0.4 archive.
- `dist/Chris_GNC_Suite-v<VERSION>.zip.sha256`: archive checksum.

Scripts are copied to `Ships/Script`; DLLs are copied to `GameData/kOS-Addons/{ATM,AFS,LTR}`, retaining the v1.0.4 package layout and adding ATM. Script, documentation and craft files come from the Git index's path list, with current working-tree content. Add new distribution files to Git before running; untracked local scripts such as `Script/boot/gt.ks` are excluded. New files under `src`, including research plugins and test outputs, are not shipped.

Existing output is refused by default. Use `-Force` to replace the selected version after the new build and ZIP checks succeed. Use `-SkipTests` only when explicitly preparing an unchecked build; it still compiles the addons and validates package contents. Output and temporary staging paths stay under `-OutputRoot`; builds leave KSP's installed files untouched.
