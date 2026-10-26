using LibreHardwareMonitor.Hardware;
using SolHelper.Logic;

namespace SolHelper.Hardware;

/// <summary>
/// Thin wrapper over LibreHardwareMonitor: opens the sensor drivers once and
/// flattens every sensor into <see cref="SensorReading"/> values.
/// </summary>
sealed class HardwareMonitor : IDisposable
{
    readonly Computer _computer;

    public HardwareMonitor()
    {
        _computer = new Computer { IsCpuEnabled = true, IsGpuEnabled = true };
        try
        {
            _computer.Open();
            Opened = true;
        }
        catch (Exception e)
        {
            // Typically: the sensor driver (PawnIO) is not installed or is blocked.
            OpenError = e.Message;
        }
    }

    public bool Opened { get; }

    public string? OpenError { get; }

    /// <summary>Names and LHM types of every GPU that has a sensor entry.</summary>
    public List<(string Name, string HardwareType)> Gpus() =>
        _computer.Hardware
            .Where(h => SensorPicker.IsGpu(h.HardwareType.ToString()))
            .Select(h => (h.Name, h.HardwareType.ToString()))
            .ToList();

    public string? CpuName() =>
        _computer.Hardware.FirstOrDefault(h => h.HardwareType == HardwareType.Cpu)?.Name;

    /// <summary>Refreshes every device and returns all sensor values.</summary>
    public List<SensorReading> Read()
    {
        var list = new List<SensorReading>();
        if (!Opened) return list;
        foreach (var hw in _computer.Hardware) Visit(hw, hw, list);
        return list;
    }

    // Sub-hardware (e.g. per-die sensors) is reported under its parent's name and
    // type so that selection by GPU name keeps working.
    static void Visit(IHardware hw, IHardware root, List<SensorReading> list)
    {
        hw.Update();
        var type = root.HardwareType.ToString();
        foreach (var s in hw.Sensors)
            list.Add(new SensorReading(type, root.Name, s.SensorType.ToString(), s.Name, s.Value));
        foreach (var sub in hw.SubHardware) Visit(sub, root, list);
    }

    public void Dispose()
    {
        try { _computer.Close(); } catch { /* best effort */ }
    }
}
