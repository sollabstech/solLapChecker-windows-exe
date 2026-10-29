using System.Diagnostics;

namespace SolHelper.Hardware;

/// <summary>
/// Puts every logical core under full load with ordinary scalar floating-point
/// and integer work, like a long render or compile. (Wide AVX loops heat a laptop
/// CPU far beyond anything real software does, so they are not used.)
/// Threads run slightly below normal priority so the UI stays responsive.
/// </summary>
sealed class CpuWorkload : IDisposable
{
    readonly List<Thread> _threads = new();
    volatile bool _stop;

    // Written once per thread so the JIT cannot discard the loop.
    static float _sink;

    public int ThreadCount { get; } = Environment.ProcessorCount;

    public void Start()
    {
        try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.BelowNormal; } catch { }

        for (var i = 0; i < ThreadCount; i++)
        {
            var seed = 1f + i * 1e-3f;
            var t = new Thread(() => Burn(seed))
            {
                IsBackground = true,
                Priority = ThreadPriority.BelowNormal,
                Name = $"cpu-stress-{i}",
            };
            _threads.Add(t);
            t.Start();
        }
    }

    void Burn(float seed)
    {
        var d = 1.0 + seed;
        var e = 2.0 - seed;
        var h = (ulong)(seed * 1_000_003) | 1;

        while (!_stop)
        {
            // Bounded recurrences: values stay finite so the ALUs never hit slow denormal/NaN paths.
            for (var i = 0; i < 200_000; i++)
            {
                d = Math.Sqrt(d * 1.0000001 + 0.5);
                e = e * 0.999999 + d * 1e-6;
                h ^= h << 13;
                h ^= h >> 7;
                h ^= h << 17;
            }
        }
        _sink = (float)(d + e) + h % 7;
    }

    public void Stop()
    {
        _stop = true;
        foreach (var t in _threads) t.Join(2000);
        _threads.Clear();
    }

    public void Dispose() => Stop();
}
