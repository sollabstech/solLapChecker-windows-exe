namespace SolHelper.Logic;

/// <summary>
/// Chooses the one meaningful temperature / clock / load out of the many
/// sensors LibreHardwareMonitor exposes. Vendors name them differently
/// (Intel "CPU Package", AMD "Core (Tctl/Tdie)", ...), so selection is by
/// preference list with sensible fallbacks.
/// </summary>
public static class SensorPicker
{
    static readonly string[] CpuTempPreference =
    {
        "CPU Package", "Core (Tctl/Tdie)", "Core (Tdie)", "Package", "Core Max",
        "Tdie", "Tctl/Tdie", "Tctl", "CPU",
    };

    public static bool IsCpu(string hardwareType) => hardwareType == "Cpu";

    public static bool IsGpu(string hardwareType) => hardwareType.StartsWith("Gpu", StringComparison.Ordinal);

    /// <summary>Junk values (0, NaN, absurd) that drivers report when a sensor is unsupported.</summary>
    public static bool ValidTemp(float? v) => v is > 0f and < 150f && float.IsFinite(v.Value);

    static bool ValidPositive(float? v) => v is > 0f && float.IsFinite(v.Value);

    static bool ValidPercent(float? v) => v is >= 0f and <= 100.5f && float.IsFinite(v.Value);

    public static float? CpuTemperature(IEnumerable<SensorReading> all)
    {
        var temps = all
            .Where(s => IsCpu(s.HardwareType) && s.SensorType == "Temperature" && ValidTemp(s.Value))
            .ToList();
        if (temps.Count == 0) return null;

        foreach (var name in CpuTempPreference)
        {
            var hit = temps.FirstOrDefault(s => s.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (hit.Value is not null) return hit.Value;
        }

        // No package sensor: the hottest core is the figure that matters.
        var cores = temps.Where(s => s.Name.Contains("Core", StringComparison.OrdinalIgnoreCase)).ToList();
        return (cores.Count > 0 ? cores : temps).Max(s => s.Value);
    }

    /// <summary>Average clock across the cores, in MHz.</summary>
    public static float? CpuClockMhz(IEnumerable<SensorReading> all)
    {
        var clocks = all
            .Where(s => IsCpu(s.HardwareType) && s.SensorType == "Clock"
                        && s.Name.Contains("Core", StringComparison.OrdinalIgnoreCase)
                        && !s.Name.Contains("Bus", StringComparison.OrdinalIgnoreCase)
                        && ValidPositive(s.Value))
            .Select(s => s.Value!.Value)
            .ToList();
        return clocks.Count == 0 ? null : clocks.Average();
    }

    public static float? CpuLoad(IEnumerable<SensorReading> all) =>
        all.Where(s => IsCpu(s.HardwareType) && s.SensorType == "Load"
                       && s.Name.Equals("CPU Total", StringComparison.OrdinalIgnoreCase)
                       && ValidPercent(s.Value))
           .Select(s => s.Value)
           .FirstOrDefault();

    public static float? CpuPowerWatts(IEnumerable<SensorReading> all) =>
        all.Where(s => IsCpu(s.HardwareType) && s.SensorType == "Power"
                       && s.Name.Equals("CPU Package", StringComparison.OrdinalIgnoreCase)
                       && ValidPositive(s.Value))
           .Select(s => s.Value)
           .FirstOrDefault();

    public static float? GpuTemperature(IEnumerable<SensorReading> all, string hardwareName)
    {
        var temps = Gpu(all, hardwareName).Where(s => s.SensorType == "Temperature" && ValidTemp(s.Value)).ToList();
        if (temps.Count == 0) return null;
        var core = temps.FirstOrDefault(s => s.Name.Equals("GPU Core", StringComparison.OrdinalIgnoreCase));
        return core.Value ?? temps.Max(s => s.Value);
    }

    public static float? GpuClockMhz(IEnumerable<SensorReading> all, string hardwareName) =>
        Gpu(all, hardwareName)
            .Where(s => s.SensorType == "Clock" && s.Name.Equals("GPU Core", StringComparison.OrdinalIgnoreCase)
                        && ValidPositive(s.Value))
            .Select(s => s.Value)
            .FirstOrDefault();

    /// <summary>
    /// 3D/compute utilisation: NVIDIA/AMD expose "GPU Core"; Intel exposes
    /// per-engine "D3D 3D" / "D3D Compute" loads.
    /// </summary>
    public static float? GpuLoad(IEnumerable<SensorReading> all, string hardwareName)
    {
        var loads = Gpu(all, hardwareName).Where(s => s.SensorType == "Load" && ValidPercent(s.Value)).ToList();
        string[] preference = { "GPU Core", "D3D 3D", "D3D Compute 0", "D3D Compute" };
        foreach (var name in preference)
        {
            var hit = loads.FirstOrDefault(s => s.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (hit.Value is not null) return hit.Value;
        }
        return loads.Count == 0 ? null : loads.Max(s => s.Value);
    }

    public static float? GpuPowerWatts(IEnumerable<SensorReading> all, string hardwareName) =>
        Gpu(all, hardwareName)
            .Where(s => s.SensorType == "Power" && ValidPositive(s.Value))
            .Select(s => s.Value)
            .FirstOrDefault();

    static IEnumerable<SensorReading> Gpu(IEnumerable<SensorReading> all, string hardwareName) =>
        all.Where(s => IsGpu(s.HardwareType) && s.HardwareName == hardwareName);
}
