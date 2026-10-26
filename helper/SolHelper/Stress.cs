using System.Diagnostics;
using SolHelper.Hardware;
using SolHelper.Logic;

namespace SolHelper;

/// <summary>What one stress test measures and loads.</summary>
interface IStressTarget : IDisposable
{
    string Test { get; }

    string DeviceName { get; }

    /// <summary>Non-null when the temperature is borrowed from another sensor (integrated GPU -> CPU package).</summary>
    string? TempSource { get; }

    /// <summary>Temperature at which throttling counts as thermal.</summary>
    float ThermalTempC { get; }

    void StartLoad();

    void StopLoad();

    /// <summary>Set if the load itself failed while running.</summary>
    string? LoadFailure { get; }

    Sample Read(IReadOnlyList<SensorReading> all);
}

/// <summary>One second's readings: the target's own, plus both temperatures for safety.</summary>
readonly record struct Sample(float? Temp, float? Clock, float? Load, float? Power, float? CpuTemp, float? GpuTemp);

sealed class CpuTarget : IStressTarget
{
    readonly CpuWorkload _load = new();

    public CpuTarget(string deviceName) => DeviceName = deviceName;

    public string Test => "cpu";
    public string DeviceName { get; }
    public string? TempSource => null;
    public float ThermalTempC => 80f;
    public string? LoadFailure => null;

    public void StartLoad() => _load.Start();
    public void StopLoad() => _load.Stop();

    public Sample Read(IReadOnlyList<SensorReading> all)
    {
        var cpuTemp = SensorPicker.CpuTemperature(all);
        return new Sample(
            cpuTemp,
            SensorPicker.CpuClockMhz(all),
            SensorPicker.CpuLoad(all),
            SensorPicker.CpuPowerWatts(all),
            cpuTemp,
            HottestGpu(all));
    }

    /// <summary>The hottest GPU, so a GPU overheating during a CPU test also trips the guard.</summary>
    static float? HottestGpu(IReadOnlyList<SensorReading> all)
    {
        float? max = null;
        foreach (var name in all.Where(s => SensorPicker.IsGpu(s.HardwareType)).Select(s => s.HardwareName).Distinct())
        {
            var t = SensorPicker.GpuTemperature(all, name);
            if (t is { } v && (max is null || v > max)) max = v;
        }
        return max;
    }

    public void Dispose() => _load.Dispose();
}

sealed class GpuTarget : IStressTarget
{
    readonly GpuAdapter _adapter;
    readonly string? _lhmName;
    readonly bool _useCpuTemp;
    GpuWorkload? _load;

    public GpuTarget(GpuAdapter adapter, string? lhmName, bool hasOwnTemp)
    {
        _adapter = adapter;
        _lhmName = lhmName;
        // Integrated GPUs share the CPU die: when they expose no sensor, the package temperature is the honest proxy.
        _useCpuTemp = !hasOwnTemp;
    }

    public string Test => "gpu";
    public string DeviceName => _adapter.Name;
    public string? TempSource => _useCpuTemp ? "cpu-package" : null;
    public float ThermalTempC => 80f;
    public string? LoadFailure => _load?.Failure;

    public void StartLoad()
    {
        _load = new GpuWorkload(GpuCatalog.Open(_adapter.Index));
        _load.Initialize();
        _load.Start();
    }

    public void StopLoad() => _load?.Stop();

    public Sample Read(IReadOnlyList<SensorReading> all)
    {
        var cpuTemp = SensorPicker.CpuTemperature(all);
        var gpuTemp = _lhmName is null ? null : SensorPicker.GpuTemperature(all, _lhmName);
        return new Sample(
            _useCpuTemp ? cpuTemp : gpuTemp,
            _lhmName is null ? null : SensorPicker.GpuClockMhz(all, _lhmName),
            _lhmName is null ? null : SensorPicker.GpuLoad(all, _lhmName),
            _lhmName is null ? null : SensorPicker.GpuPowerWatts(all, _lhmName),
            cpuTemp,
            gpuTemp);
    }

    public void Dispose() => _load?.Dispose();
}

/// <summary>
/// Runs one stress test: applies the load, samples sensors once a second,
/// enforces the safety limit, detects throttling and emits the final summary.
/// </summary>
static class StressRunner
{
    public static async Task<int> Run(
        IStressTarget target,
        HardwareMonitor monitor,
        int durationSec,
        float limitC,
        bool pawnIo,
        CancellationToken stop)
    {
        // Refuse to heat the machine if we cannot watch its temperature.
        var first = target.Read(monitor.Read());
        if (first.Temp is null)
        {
            Protocol.Emit(new ErrorEvent(
                "no-temperature",
                monitor.OpenError is { } err
                    ? $"The hardware sensor driver could not be loaded ({err})."
                    : pawnIo
                        ? "No temperature sensor could be read on this device."
                        : "No temperature sensor could be read. The PawnIO sensor driver is not installed."));
            return 3;
        }

        Protocol.Emit(new StartEvent(target.Test, durationSec, limitC, target.DeviceName, target.TempSource));

        var guard = new SafetyGuard(limitC);
        var throttle = new ThrottleDetector(target.ThermalTempC);
        RunningStats temp = new(), clock = new(), load = new(), cpuTemp = new(), gpuTemp = new();

        var reason = "completed";
        string? message = null;
        var sw = Stopwatch.StartNew();
        var seconds = 0;

        try
        {
            target.StartLoad();

            for (var t = 1; t <= durationSec; t++)
            {
                var wait = TimeSpan.FromSeconds(t) - sw.Elapsed;
                if (wait > TimeSpan.Zero) await Task.Delay(wait, stop);

                seconds = t;
                var s = target.Read(monitor.Read());

                temp.Add(s.Temp);
                clock.Add(s.Clock);
                load.Add(s.Load);
                cpuTemp.Add(s.CpuTemp);
                gpuTemp.Add(s.GpuTemp);
                throttle.Add(t, s.Clock, s.Temp, s.Load);

                Protocol.Emit(new SampleEvent(
                    t, Protocol.R(s.Temp), Protocol.R(s.Clock), Protocol.R(s.Load),
                    Protocol.R(s.Power), Protocol.R(s.CpuTemp), Protocol.R(s.GpuTemp)));

                if (target.LoadFailure is { } fail)
                {
                    reason = "error";
                    message = $"The test load failed: {fail}";
                    break;
                }

                if (guard.Check(s.Temp, s.CpuTemp, s.GpuTemp) is { } abort)
                {
                    reason = "safety";
                    message = abort;
                    break;
                }
            }
        }
        catch (OperationCanceledException)
        {
            reason = "stopped";
        }
        catch (Exception e)
        {
            reason = "error";
            message = e.Message;
        }
        finally
        {
            // Always remove the load, whatever happened.
            try { target.StopLoad(); } catch { }
        }

        Protocol.Emit(new EndEvent(
            target.Test, reason, message, seconds, temp.Count,
            Protocol.R(temp.Max), Protocol.R(temp.Average), Protocol.R(temp.Min),
            Protocol.R(clock.Max), Protocol.R(throttle.State == ThrottleState.None ? clock.Min : throttle.LowestClockMhz),
            Protocol.R(load.Average),
            Protocol.R(cpuTemp.Max), Protocol.R(gpuTemp.Max),
            throttle.State == ThrottleState.Thermal,
            throttle.State == ThrottleState.PowerLimit,
            throttle.Note));

        return reason == "error" ? 1 : 0;
    }
}
