using System;
using Mono.Cecil;
class InspectThreading
{
    static void Inspect(string file,string typeName,params string[] names)
    {
        var assembly=AssemblyDefinition.ReadAssembly(file);
        {
            Console.WriteLine("ASSEMBLY "+assembly.Name+" MVID "+assembly.MainModule.Mvid);
            TypeDefinition type=assembly.MainModule.GetType(typeName);
            foreach(MethodDefinition method in type.Methods)
            {
                if(Array.IndexOf(names,method.Name)<0)continue;
                Console.WriteLine("METHOD "+method.FullName);
                foreach(CustomAttribute attr in method.CustomAttributes)
                {
                    Console.WriteLine("ATTRIBUTE "+attr.AttributeType.FullName);
                    foreach(var field in attr.Fields)Console.WriteLine("  "+field.Name+"="+field.Argument.Value);
                    foreach(var property in attr.Properties)Console.WriteLine("  "+property.Name+"="+property.Argument.Value);
                }
                if(method.HasBody)foreach(var instruction in method.Body.Instructions)
                    if(instruction.OpCode.Name.StartsWith("call")||instruction.OpCode.Name.StartsWith("ldfld")||instruction.OpCode.Name.StartsWith("stfld"))Console.WriteLine(instruction);
            }
        }
    }
    static void Main(string[] args)
    {
        string managed=args[0];
        Inspect(System.IO.Path.Combine(managed,"Assembly-CSharp.dll"),"CelestialBody","GetAtmoThermalStats","GetFullTemperature","GetPressure","GetTemperature","GetDensity");
        Inspect(System.IO.Path.Combine(managed,"Assembly-CSharp.dll"),"FloatCurve","Evaluate");
        Inspect(System.IO.Path.Combine(managed,"UnityEngine.CoreModule.dll"),"UnityEngine.AnimationCurve","Evaluate");
        Inspect(System.IO.Path.Combine(managed,"UnityEngine.CoreModule.dll"),"UnityEngine.Transform","get_position","get_up","get_rotation");
        Inspect(System.IO.Path.Combine(managed,"UnityEngine.CoreModule.dll"),"UnityEngine.Quaternion","AngleAxis","op_Multiply");
    }
}
