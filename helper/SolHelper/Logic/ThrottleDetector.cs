namespace SolHelper.Logic;

public enum ThrottleState
{
    None,

    /// <summary>Clock fell well below its peak while the part was hot: a cooling problem.</summary>
    Thermal,

    /// <summary>Clock fell while the part was not hot: normal boost decay or a power cap.</summary>
    PowerLimit,
}

/// <summary>
/// Detects throttling from the clock/temperature trace of a stress test.
///
/// A clock that stays below <see cref="DropRatio"/> of the peak sustained clock for
/// <see cref="ConsecutiveLowSamples"/> seconds in a row, while fully loaded, is throttling
/// (a brief stutter is ignored; the peak itself is taken from a smoothed trace). If the part was at or
/// above <see cref="ThermalTempC"/> it is classed as thermal; otherwise it is only
/// a power/boost limit, which most thin laptops show and which is not a defect.
/// </summary>
public sealed class ThrottleDetector
{
    public const double DropRatio = 0.85;
    public const int WarmupSeconds = 3;
    public const int MinSecondsBeforeJudging = 10;
    public const int ConsecutiveLowSamples = 5;
    public const int SmoothingWindow = 3;

    readonly float _thermalTempC;
    readonly float _minLoad;
    readonly List<float> _window = new();
    int _lowRun;
    double _lowSum;

    public ThrottleDetector(float thermalTempC = 80f, float minLoadPercent = 80f)
    {
        _thermalTempC = thermalTempC;
        _minLoad = minLoadPercent;
    }

    public ThrottleState State { get; private set; } = ThrottleState.None;

    /// <summary>Highest smoothed clock seen under load, in MHz.</summary>
    public double PeakClockMhz { get; private set; }

    /// <summary>Lowest smoothed clock seen after the peak, in MHz.</summary>
    public double LowestClockMhz { get; private set; } = double.MaxValue;

    public float? TempAtThrottle { get; private set; }

    public string? Note { get; private set; }

    public void Add(int second, float? clockMhz, float? tempC, float? loadPercent)
    {
        if (clockMhz is not > 0 || second < WarmupSeconds) return;
        // Unknown load is assumed to be loaded: the workload is running.
        if (loadPercent is { } l && l < _minLoad) { _lowRun = 0; return; }

        _window.Add(clockMhz.Value);
        if (_window.Count > SmoothingWindow) _window.RemoveAt(0);
        if (_window.Count < SmoothingWindow) return;

        var smooth = _window.Average();

        // The peak only rises while the clock is healthy, so a throttled
        // plateau never becomes the new baseline.
        if (smooth > PeakClockMhz && _lowRun == 0) PeakClockMhz = smooth;

        if (second < MinSecondsBeforeJudging || PeakClockMhz <= 0) return;

        var raw = clockMhz.Value;
        if (raw < PeakClockMhz * DropRatio)
        {
            _lowRun++;
            _lowSum += raw;
            if (_lowRun >= ConsecutiveLowSamples)
            {
                LowestClockMhz = Math.Min(LowestClockMhz, _lowSum / _lowRun);
                var hot = tempC is { } t && t >= _thermalTempC;
                if (hot)
                {
                    State = ThrottleState.Thermal;
                    TempAtThrottle ??= tempC;
                    Note = $"Clock dropped from {PeakClockMhz:0} to {LowestClockMhz:0} MHz at {TempAtThrottle:0} °C (thermal throttling).";
                }
                else if (State != ThrottleState.Thermal)
                {
                    State = ThrottleState.PowerLimit;
                    Note = $"Clock settled from {PeakClockMhz:0} to {LowestClockMhz:0} MHz without overheating (power/boost limit).";
                }
            }
        }
        else
        {
            _lowRun = 0;
            _lowSum = 0;
        }
    }
}
