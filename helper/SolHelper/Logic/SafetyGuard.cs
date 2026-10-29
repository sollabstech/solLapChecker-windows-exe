namespace SolHelper.Logic;

/// <summary>
/// Decides when a stress test must be aborted.
///
/// * A GPU at or above the limit (95 °C by default) stops the test at once.
/// * A CPU is judged differently: laptop CPUs boost straight to 95-100 °C under
///   full load (Intel's TjMax is 100 °C, where the chip slows itself down), so a
///   brief peak is normal. Only a CPU that stays at <see cref="CpuSustainedLimitC"/>
///   for <see cref="CpuSustainSeconds"/> seconds in a row, or reaches
///   <see cref="CpuHardLimitC"/>, stops the test.
/// * The watched sensor going dark while load is applied also stops it.
/// </summary>
public sealed class SafetyGuard
{
    public const float DefaultLimitC = 95f;
    public const float CpuSustainedLimitC = 98f;
    public const int CpuSustainSeconds = 15;
    public const float CpuHardLimitC = 105f;
    public const int MaxBlindSeconds = 5;

    readonly float _limit;
    int _blind;
    int _cpuHot;

    public SafetyGuard(float limitC = DefaultLimitC) => _limit = limitC;

    public float LimitC => _limit;

    /// <summary>Returns a human-readable abort reason, or null if the test may continue.</summary>
    /// <param name="watchedC">Temperature the test is watched by; null when unreadable.</param>
    /// <param name="watchedIsCpu">That temperature is the CPU's (CPU test, or an integrated GPU without a sensor).</param>
    /// <param name="cpuC">CPU temperature, when known.</param>
    /// <param name="gpuC">Hottest GPU temperature, when known.</param>
    public string? Check(float? watchedC, bool watchedIsCpu, float? cpuC = null, float? gpuC = null)
    {
        if (!watchedIsCpu && watchedC is { } w && w >= _limit) return Reached(w, _limit);
        if (gpuC is { } g && g >= _limit) return Reached(g, _limit);

        var cpu = watchedIsCpu ? watchedC ?? cpuC : cpuC;
        if (cpu is { } c)
        {
            if (c >= CpuHardLimitC) return Reached(c, CpuHardLimitC);
            _cpuHot = c >= CpuSustainedLimitC ? _cpuHot + 1 : 0;
            if (_cpuHot >= CpuSustainSeconds)
                return $"The processor stayed at {CpuSustainedLimitC:0} °C or more for {CpuSustainSeconds} seconds.";
        }
        else
        {
            _cpuHot = 0;
        }

        _blind = watchedC is null ? _blind + 1 : 0;
        if (_blind >= MaxBlindSeconds)
            return "The temperature sensor stopped responding, so the test was stopped for safety.";

        return null;
    }

    static string Reached(float t, float limit) => $"Reached {t:0} °C (limit {limit:0} °C).";
}
