using System.Security.Principal;
using Microsoft.Win32;
using SolHelper;
using SolHelper.Hardware;
using SolHelper.Logic;

// SolHelper: hardware tasks for SolLapChecker that Flutter cannot do itself.
//
//   SolHelper info                                   one "info" line, then exit
//   SolHelper cpu-stress --duration 60 [--limit 95]  sample lines until the test ends
//   SolHelper gpu-stress --gpu 1 --duration 60 [--limit 95]
//
// Output: JSON lines on stdout (see Protocol.cs). Input: a line "stop" on stdin ends the
// test early; closing stdin (the parent app exiting) does the same.

const string Version = "1.0.0";

return await Main2(args);

static async Task<int> Main2(string[] args)
{
    var cmd = args.FirstOrDefault()?.ToLowerInvariant();
    var opts = ParseOptions(args.Skip(1).ToArray());

    var duration = Math.Clamp(IntOpt(opts, "duration", 60), 5, 3600);
    var limit = Math.Clamp(FloatOpt(opts, "limit", SafetyGuard.DefaultLimitC), 60f, 105f);

    switch (cmd)
    {
        case "info":
            return Info();
        case "cpu-stress":
        case "gpu-stress":
            return await Stress(cmd, opts, duration, limit);
        default:
            Console.Error.WriteLine("Usage: SolHelper info | cpu-stress --duration N [--limit C] | gpu-stress --gpu I --duration N [--limit C]");
            return 2;
    }
}

static int Info()
{
    using var monitor = new HardwareMonitor();
    var sensors = monitor.Read();

    List<GpuAdapter> adapters;
    try { adapters = GpuCatalog.Enumerate(); }
    catch (Exception e)
    {
        Console.Error.WriteLine($"DXGI enumeration failed: {e.Message}");
        adapters = new();
    }

    var lhmGpus = monitor.Gpus();
    var gpus = adapters.Select(a =>
    {
        var i = GpuMatcher.Match(a.Name, a.VendorId, lhmGpus);
        var own = i >= 0 && SensorPicker.GpuTemperature(sensors, lhmGpus[i].Name) is not null;
        var anyTemp = own || SensorPicker.CpuTemperature(sensors) is not null;
        return new GpuDto(a.Index, a.Name, a.Integrated ? "integrated" : "dedicated",
            (long)(a.DedicatedBytes >> 20), anyTemp, own);
    }).ToList();

    var cpuTemp = SensorPicker.CpuTemperature(sensors);
    Protocol.Emit(new InfoEvent(
        Version, IsAdmin(), IsPawnIoInstalled(), monitor.OpenError,
        monitor.CpuName(), cpuTemp is not null, Protocol.R(cpuTemp), gpus));
    return 0;
}

static async Task<int> Stress(string cmd, Dictionary<string, string> opts, int duration, float limit)
{
    using var monitor = new HardwareMonitor();
    using var cts = new CancellationTokenSource();
    WatchStdin(cts);
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

    IStressTarget target;
    if (cmd == "cpu-stress")
    {
        target = new CpuTarget(monitor.CpuName() ?? "CPU");
    }
    else
    {
        var index = IntOpt(opts, "gpu", -1);
        GpuAdapter? adapter;
        try { adapter = GpuCatalog.Enumerate().FirstOrDefault(a => a.Index == index); }
        catch (Exception e)
        {
            Protocol.Emit(new ErrorEvent("gpu-enumeration", $"Could not list GPUs: {e.Message}"));
            return 1;
        }
        if (adapter is null)
        {
            Protocol.Emit(new ErrorEvent("gpu-not-found", $"No GPU with index {index}."));
            return 1;
        }

        var lhm = monitor.Gpus();
        var m = GpuMatcher.Match(adapter.Name, adapter.VendorId, lhm);
        var lhmName = m >= 0 ? lhm[m].Name : null;
        var own = lhmName is not null && SensorPicker.GpuTemperature(monitor.Read(), lhmName) is not null;
        target = new GpuTarget(adapter, lhmName, own);
    }

    using (target)
    {
        try
        {
            return await StressRunner.Run(target, monitor, duration, limit, IsPawnIoInstalled(), cts.Token);
        }
        catch (Exception e)
        {
            // Includes GPU device/shader creation failures raised by StartLoad.
            Protocol.Emit(new ErrorEvent("start-failed", e.Message));
            return 1;
        }
    }
}

/// <summary>Cancels the test when the parent sends "stop" or closes our stdin.</summary>
static void WatchStdin(CancellationTokenSource cts)
{
    var t = new Thread(() =>
    {
        try
        {
            while (true)
            {
                var line = Console.In.ReadLine();
                if (line is null || line.Trim().Equals("stop", StringComparison.OrdinalIgnoreCase))
                {
                    cts.Cancel();
                    return;
                }
            }
        }
        catch
        {
            cts.Cancel();
        }
    })
    { IsBackground = true, Name = "stdin-watch" };
    t.Start();
}

static bool IsAdmin()
{
    using var id = WindowsIdentity.GetCurrent();
    return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
}

/// <summary>LibreHardwareMonitorLib 0.9.5+ reads CPU sensors through the PawnIO driver.</summary>
static bool IsPawnIoInstalled()
{
    try
    {
        return Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PawnIO", "ImagePath", null) is not null;
    }
    catch
    {
        return false;
    }
}

static Dictionary<string, string> ParseOptions(string[] args)
{
    var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    for (var i = 0; i < args.Length; i++)
    {
        if (!args[i].StartsWith("--", StringComparison.Ordinal)) continue;
        var key = args[i][2..];
        map[key] = i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal) ? args[++i] : "true";
    }
    return map;
}

static int IntOpt(Dictionary<string, string> o, string key, int fallback) =>
    o.TryGetValue(key, out var v) && int.TryParse(v, out var n) ? n : fallback;

static float FloatOpt(Dictionary<string, string> o, string key, float fallback) =>
    o.TryGetValue(key, out var v) && float.TryParse(v, System.Globalization.CultureInfo.InvariantCulture, out var n) ? n : fallback;
