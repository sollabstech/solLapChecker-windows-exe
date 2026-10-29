using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SolHelper;

/// <summary>
/// Output side of the helper's protocol: one JSON object per line on stdout,
/// each with a "type" field. The Flutter app reads these lines as they arrive.
/// Diagnostics never go to stdout, only to stderr.
/// </summary>
static class Protocol
{
    static readonly object Gate = new();

    static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    static readonly StreamWriter Out = new(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };

    public static void Emit(object evt)
    {
        var line = JsonSerializer.Serialize(evt, evt.GetType(), Options);
        lock (Gate) Out.WriteLine(line);
    }

    /// <summary>Rounds to one decimal and maps NaN/∞ to null so the JSON stays valid.</summary>
    public static double? R(double? v) => v is { } d && double.IsFinite(d) ? Math.Round(d, 1) : null;

    public static double? R(float? v) => v is { } f ? R((double)f) : null;
}

record GpuDto(int Index, string Name, string Kind, long DedicatedMb, bool HasTempSensor, bool HasOwnTempSensor);

record InfoEvent(
    string Version,
    bool Admin,
    bool PawnIo,
    string? SensorError,
    string? CpuName,
    bool CpuTempAvailable,
    double? CpuTempC,
    List<GpuDto> Gpus)
{
    public string Type => "info";
}

record StartEvent(string Test, int DurationSec, double LimitC, string Device, string? TempSource)
{
    public string Type => "start";
}

record SampleEvent(
    int T,
    double? TempC,
    double? ClockMhz,
    double? LoadPct,
    double? PowerW,
    double? CpuTempC,
    double? GpuTempC)
{
    public string Type => "sample";
}

record FaceEvent(int Faces, int Width, int Height)
{
    public string Type => "face";
}

record WarningEvent(string Message)
{
    public string Type => "warning";
}

record ErrorEvent(string Code, string Message)
{
    public string Type => "error";
}

record EndEvent(
    string Test,
    string Reason,
    string? Message,
    int ElapsedSec,
    int Samples,
    double? MaxTempC,
    double? AvgTempC,
    double? MinTempC,
    double? MaxClockMhz,
    double? MinClockMhz,
    double? AvgLoadPct,
    double? MaxCpuTempC,
    double? MaxGpuTempC,
    bool Throttled,
    bool PowerLimited,
    string? ThrottleNote)
{
    public string Type => "end";
}
