namespace SolHelper.Logic;

/// <summary>Min / max / average of a stream of optional values.</summary>
public sealed class RunningStats
{
    double _sum;

    public int Count { get; private set; }
    public double? Max { get; private set; }
    public double? Min { get; private set; }
    public double? Average => Count == 0 ? null : _sum / Count;

    public void Add(float? value)
    {
        if (value is not { } v || !float.IsFinite(v)) return;
        Count++;
        _sum += v;
        Max = Max is null ? v : Math.Max(Max.Value, v);
        Min = Min is null ? v : Math.Min(Min.Value, v);
    }
}
