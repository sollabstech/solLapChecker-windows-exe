namespace SolHelper.Logic;

/// <summary>
/// One sensor value, decoupled from LibreHardwareMonitor so the selection
/// logic below can be unit-tested without hardware.
/// </summary>
/// <param name="HardwareType">LHM HardwareType name, e.g. "Cpu", "GpuNvidia", "GpuAmd", "GpuIntel".</param>
/// <param name="HardwareName">e.g. "Intel Core i7-1260P" or "NVIDIA GeForce RTX 3060 Laptop GPU".</param>
/// <param name="SensorType">LHM SensorType name: "Temperature", "Clock", "Load", "Power".</param>
public readonly record struct SensorReading(
    string HardwareType,
    string HardwareName,
    string SensorType,
    string Name,
    float? Value);
