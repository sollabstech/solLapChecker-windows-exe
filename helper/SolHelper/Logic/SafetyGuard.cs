namespace SolHelper.Logic;

/// <summary>
/// Decides when a stress test must be aborted: any monitored temperature at or
/// above the limit, or the temperature sensor going dark while load is applied.
/// </summary>
public sealed class SafetyGuard
{
    public const float DefaultLimitC = 95f;
    public const int MaxBlindSeconds = 5;

    readonly float _limit;
    int _blind;

    public SafetyGuard(float limitC = DefaultLimitC) => _limit = limitC;

    public float LimitC => _limit;

    /// <summary>Returns a human-readable abort reason, or null if the test may continue.</summary>
    /// <param name="primaryTempC">Temperature of the part under test; null when unreadable.</param>
    /// <param name="otherTempsC">Other monitored parts (e.g. the CPU during a GPU test).</param>
    public string? Check(float? primaryTempC, params float?[] otherTempsC)
    {
        if (primaryTempC is { } p && p >= _limit)
            return $"Reached {p:0} °C (limit {_limit:0} °C).";

        foreach (var t in otherTempsC)
            if (t is { } o && o >= _limit)
                return $"Reached {o:0} °C (limit {_limit:0} °C).";

        _blind = primaryTempC is null ? _blind + 1 : 0;
        if (_blind >= MaxBlindSeconds)
            return "The temperature sensor stopped responding, so the test was stopped for safety.";

        return null;
    }
}
