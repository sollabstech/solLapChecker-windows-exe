using System.Diagnostics;
using System.Numerics;

namespace SolHelper.Hardware;

/// <summary>
/// Puts every logical core under full load with a tight SIMD + sqrt loop.
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
        var a = new Vector<float>(seed);
        var b = new Vector<float>(0.9999f);
        var c = new Vector<float>(0.0001f);
        var d = 1.0 + seed;

        while (!_stop)
        {
            // Bounded recurrences: values stay finite so the ALUs never hit slow denormal/NaN paths.
            for (var i = 0; i < 200_000; i++)
            {
                a = a * b + c;
                b = Vector.SquareRoot(b * b + c);
                c = (a + b) * new Vector<float>(0.5f) * new Vector<float>(0.0001f);
                d = Math.Sqrt(d * 1.0000001 + 0.5);
            }
        }
        _sink = a[0] + b[0] + c[0] + (float)d;
    }

    public void Stop()
    {
        _stop = true;
        foreach (var t in _threads) t.Join(2000);
        _threads.Clear();
    }

    public void Dispose() => Stop();
}
