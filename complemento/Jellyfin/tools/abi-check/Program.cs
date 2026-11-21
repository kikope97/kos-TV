// Kos TV: checks the built plugin against the Jellyfin assemblies this tool was built with
// (see AbiCheck.csproj). The plugin is compiled against Jellyfin 10.10, so a member Jellyfin
// changed later (a return type, a property gone) still compiles and only fails on the server,
// with MissingMethodException, when the method using it first runs. This finds those here:
//  - the plugin's types load (what Jellyfin does on loading a plugin);
//  - every type and member the plugin references resolves;
//  - every method compiles (JIT);
//  - every scheduled task gives its default triggers.
// Exit code 0 when all is well, 1 when something is broken, 2 on bad usage.
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Runtime.CompilerServices;
using System.Runtime.Loader;

if (args.Length != 1 || !File.Exists(args[0]))
{
    Console.Error.WriteLine("Usage: AbiCheck <path-to-Moonfin.Server.dll>");
    return 2;
}

var dll = Path.GetFullPath(args[0]);
var dir = Path.GetDirectoryName(dll)!;
// What the plugin ships beside it (SharpCompress); Jellyfin's own come with this tool.
AssemblyLoadContext.Default.Resolving += (context, name) =>
{
    var path = Path.Combine(dir, name.Name + ".dll");
    return File.Exists(path) ? context.LoadFromAssemblyPath(path) : null;
};

var jellyfin = typeof(MediaBrowser.Controller.Library.ILibraryManager).Assembly.GetName().Version;
Console.WriteLine($"Jellyfin {jellyfin}: {dll}");

var problems = new List<string>();
var asm = AssemblyLoadContext.Default.LoadFromAssemblyPath(dll);

// 1. The types load.
Type[] types;
try
{
    types = asm.GetTypes();
}
catch (ReflectionTypeLoadException ex)
{
    foreach (var message in ex.LoaderExceptions.OfType<Exception>().Select(e => e.Message).Distinct())
    {
        problems.Add("type load: " + message);
    }

    types = ex.Types.OfType<Type>().ToArray();
}

// 2. Every type and member referenced resolves.
var resolved = 0;
using (var stream = File.OpenRead(dll))
using (var pe = new PEReader(stream))
{
    var metadata = pe.GetMetadataReader();
    var module = asm.ManifestModule;
    var seen = new HashSet<string>();
    void Resolve(EntityHandle handle, bool isType)
    {
        var token = MetadataTokens.GetToken(handle);
        try
        {
            _ = isType ? module.ResolveType(token) : module.ResolveMember(token);
            resolved++;
        }
        catch (ArgumentException)
        {
            // A member of an open generic type: it needs a generic context to resolve, and is
            // checked when the methods using it compile (3).
        }
        catch (Exception ex)
        {
            var inner = ex is TargetInvocationException { InnerException: { } i } ? i : ex;
            if (seen.Add(inner.Message))
            {
                problems.Add($"reference: {inner.GetType().Name}: {inner.Message}");
            }
        }
    }

    foreach (var handle in metadata.TypeReferences)
    {
        Resolve(handle, isType: true);
    }

    foreach (var handle in metadata.MemberReferences)
    {
        Resolve(handle, isType: false);
    }
}

// 3. Every method compiles.
const BindingFlags All = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly;
var compiled = 0;
var failures = new SortedDictionary<string, List<string>>();
foreach (var type in types.Where(t => !t.ContainsGenericParameters))
{
    MethodBase[] methods;
    try
    {
        methods = [.. type.GetMethods(All), .. type.GetConstructors(All)];
    }
    catch (Exception ex)
    {
        problems.Add($"type {type.FullName}: {ex.Message}");
        continue;
    }

    foreach (var method in methods)
    {
        // A delegate's BeginInvoke/EndInvoke never compile on .NET (Core), on any server.
        if (method.IsAbstract || method.ContainsGenericParameters ||
            (typeof(Delegate).IsAssignableFrom(type) && method.Name is "BeginInvoke" or "EndInvoke"))
        {
            continue;
        }

        try
        {
            RuntimeHelpers.PrepareMethod(method.MethodHandle);
            compiled++;
        }
        catch (Exception ex)
        {
            var inner = ex is TargetInvocationException { InnerException: { } i } ? i : ex;
            var key = $"{inner.GetType().Name}: {inner.Message}";
            if (!failures.TryGetValue(key, out var where))
            {
                failures[key] = where = [];
            }

            where.Add($"{type.FullName}::{method.Name}");
        }
    }
}

foreach (var (message, where) in failures)
{
    problems.Add($"compile: {message}\n      in {string.Join("\n      in ", where.Take(10))}{(where.Count > 10 ? $"\n      … and {where.Count - 10} more" : string.Empty)}");
}

// 4. Every scheduled task gives its default triggers (they don't read the task's state).
var tasks = 0;
foreach (var type in types.Where(t => !t.IsAbstract && !t.ContainsGenericParameters && t.GetInterfaces().Any(i => i.FullName == "MediaBrowser.Model.Tasks.IScheduledTask")))
{
    tasks++;
    try
    {
        var task = RuntimeHelpers.GetUninitializedObject(type);
        var triggers = ((System.Collections.IEnumerable)type.GetMethod("GetDefaultTriggers")!.Invoke(task, null)!).Cast<object>().ToList();
        foreach (var trigger in triggers)
        {
            if (trigger.GetType().GetProperty("Type")?.GetValue(trigger) is not { } kind || kind.ToString() is null or "")
            {
                problems.Add($"triggers: {type.FullName} gives a trigger without its type");
            }
        }
    }
    catch (Exception ex)
    {
        var inner = ex is TargetInvocationException { InnerException: { } i } ? i : ex;
        problems.Add($"triggers: {type.FullName}: {inner.GetType().Name}: {inner.Message}");
    }
}

Console.WriteLine($"  {types.Length} types, {resolved} references, {compiled} methods, {tasks} scheduled tasks");
foreach (var problem in problems)
{
    Console.WriteLine("  BROKEN " + problem);
}

Console.WriteLine(problems.Count == 0 ? "  OK" : $"  {problems.Count} broken");
return problems.Count == 0 ? 0 : 1;
