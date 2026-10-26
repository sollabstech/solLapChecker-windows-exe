using SolHelper.Logic;
using Xunit;

namespace SolHelper.Tests;

public class SensorPickerTests
{
    static SensorReading Cpu(string type, string name, float? v) => new("Cpu", "Intel Core i7-1260P", type, name, v);

    [Fact]
    public void Intel_prefers_the_package_temperature()
    {
        var all = new[]
        {
            Cpu("Temperature", "CPU Core #1", 71),
            Cpu("Temperature", "CPU Core #2", 74),
            Cpu("Temperature", "CPU Package", 76),
        };
        Assert.Equal(76f, SensorPicker.CpuTemperature(all));
    }

    [Fact]
    public void AMD_uses_Tctl_Tdie()
    {
        var all = new[] { Cpu("Temperature", "Core (Tctl/Tdie)", 83), Cpu("Temperature", "CCD1 (Tdie)", 80) };
        Assert.Equal(83f, SensorPicker.CpuTemperature(all));
    }

    [Fact]
    public void Without_a_package_sensor_the_hottest_core_wins()
    {
        var all = new[] { Cpu("Temperature", "CPU Core #1", 60), Cpu("Temperature", "CPU Core #2", 68) };
        Assert.Equal(68f, SensorPicker.CpuTemperature(all));
    }

    [Fact]
    public void Junk_values_are_ignored()
    {
        var all = new[]
        {
            Cpu("Temperature", "CPU Package", 0),
            Cpu("Temperature", "CPU Core #1", float.NaN),
            Cpu("Temperature", "CPU Core #2", 255),
        };
        Assert.Null(SensorPicker.CpuTemperature(all));
    }

    [Fact]
    public void Cpu_clock_is_the_core_average_and_skips_the_bus_clock()
    {
        var all = new[]
        {
            Cpu("Clock", "CPU Core #1", 4000),
            Cpu("Clock", "CPU Core #2", 3000),
            Cpu("Clock", "Bus Speed", 100),
        };
        Assert.Equal(3500f, SensorPicker.CpuClockMhz(all));
    }

    [Fact]
    public void Cpu_load_and_power()
    {
        var all = new[] { Cpu("Load", "CPU Total", 98.5f), Cpu("Load", "CPU Core #1", 10), Cpu("Power", "CPU Package", 28) };
        Assert.Equal(98.5f, SensorPicker.CpuLoad(all));
        Assert.Equal(28f, SensorPicker.CpuPowerWatts(all));
    }

    [Fact]
    public void Gpu_sensors_are_scoped_to_the_named_card()
    {
        const string dgpu = "NVIDIA GeForce RTX 3060 Laptop GPU";
        var all = new[]
        {
            new SensorReading("GpuNvidia", dgpu, "Temperature", "GPU Core", 66),
            new SensorReading("GpuNvidia", dgpu, "Clock", "GPU Core", 1700),
            new SensorReading("GpuNvidia", dgpu, "Load", "GPU Core", 99),
            new SensorReading("GpuIntel", "Intel UHD Graphics", "Load", "D3D 3D", 3),
        };
        Assert.Equal(66f, SensorPicker.GpuTemperature(all, dgpu));
        Assert.Equal(1700f, SensorPicker.GpuClockMhz(all, dgpu));
        Assert.Equal(99f, SensorPicker.GpuLoad(all, dgpu));
        Assert.Null(SensorPicker.GpuTemperature(all, "Intel UHD Graphics")); // iGPU has no own sensor
        Assert.Equal(3f, SensorPicker.GpuLoad(all, "Intel UHD Graphics"));
    }
}

public class ThrottleDetectorTests
{
    /// <summary>Feeds one sample per second from a clock/temp function.</summary>
    static ThrottleDetector Run(int seconds, Func<int, float> clock, Func<int, float> temp, float load = 100)
    {
        var d = new ThrottleDetector();
        for (var t = 1; t <= seconds; t++) d.Add(t, clock(t), temp(t), load);
        return d;
    }

    [Fact]
    public void Steady_clock_is_not_throttling()
    {
        var d = Run(60, _ => 3800, t => 70 + t * 0.1f);
        Assert.Equal(ThrottleState.None, d.State);
        Assert.Null(d.Note);
    }

    [Fact]
    public void Clock_collapse_while_hot_is_thermal_throttling()
    {
        var d = Run(60, t => t < 20 ? 4500 : 2800, t => t < 20 ? 80 : 94);
        Assert.Equal(ThrottleState.Thermal, d.State);
        Assert.InRange(d.PeakClockMhz, 4400, 4600);
        Assert.NotNull(d.TempAtThrottle);
        Assert.Contains("thermal", d.Note);
    }

    [Fact]
    public void Clock_decay_without_heat_is_only_a_power_limit()
    {
        var d = Run(60, t => t < 20 ? 4800 : 3600, _ => 72);
        Assert.Equal(ThrottleState.PowerLimit, d.State);
        Assert.Contains("power", d.Note);
    }

    [Fact]
    public void A_power_limit_that_later_overheats_becomes_thermal()
    {
        var d = Run(80, t => t < 20 ? 4800 : 3500, t => t < 50 ? 72 : 92);
        Assert.Equal(ThrottleState.Thermal, d.State);
    }

    [Fact]
    public void A_brief_dip_is_ignored()
    {
        var d = Run(60, t => t is 30 or 31 ? 2000 : 4000, _ => 90);
        Assert.Equal(ThrottleState.None, d.State);
    }

    [Fact]
    public void Drops_while_idle_are_ignored()
    {
        var d = new ThrottleDetector();
        for (var t = 1; t <= 40; t++) d.Add(t, t < 15 ? 4500 : 1200, 90, t < 15 ? 100 : 5);
        Assert.Equal(ThrottleState.None, d.State);
    }

    [Fact]
    public void Missing_clock_data_never_flags_throttling()
    {
        var d = new ThrottleDetector();
        for (var t = 1; t <= 60; t++) d.Add(t, null, 95, 100);
        Assert.Equal(ThrottleState.None, d.State);
    }
}

public class SafetyGuardTests
{
    [Fact]
    public void Stops_at_exactly_the_limit()
    {
        var g = new SafetyGuard(95);
        Assert.Null(g.Check(94.9f));
        Assert.NotNull(g.Check(95f));
    }

    [Fact]
    public void Another_part_reaching_the_limit_also_stops_the_test()
    {
        var g = new SafetyGuard(95);
        var reason = g.Check(60f, 96f);
        Assert.NotNull(reason);
        Assert.Contains("96", reason);
    }

    [Fact]
    public void Losing_the_sensor_stops_the_test_after_five_blind_seconds()
    {
        var g = new SafetyGuard(95);
        for (var i = 0; i < SafetyGuard.MaxBlindSeconds - 1; i++) Assert.Null(g.Check(null));
        Assert.NotNull(g.Check(null));
    }

    [Fact]
    public void A_valid_reading_resets_the_blind_counter()
    {
        var g = new SafetyGuard(95);
        for (var i = 0; i < 4; i++) g.Check(null);
        Assert.Null(g.Check(70f));
        for (var i = 0; i < 4; i++) Assert.Null(g.Check(null));
    }
}

public class GpuMatcherTests
{
    static readonly (string, string)[] Lhm =
    {
        ("Intel UHD Graphics", "GpuIntel"),
        ("NVIDIA GeForce RTX 3060 Laptop GPU", "GpuNvidia"),
    };

    [Fact]
    public void Matches_by_normalised_name()
    {
        Assert.Equal(1, GpuMatcher.Match("NVIDIA GeForce RTX 3060 Laptop GPU", GpuMatcher.VendorNvidia, Lhm));
        Assert.Equal(0, GpuMatcher.Match("Intel(R) UHD Graphics", GpuMatcher.VendorIntel, Lhm));
    }

    [Fact]
    public void Falls_back_to_the_only_card_of_that_vendor()
    {
        Assert.Equal(1, GpuMatcher.Match("NVIDIA RTX A2000", GpuMatcher.VendorNvidia, Lhm));
    }

    [Fact]
    public void Ambiguous_or_unknown_vendor_is_no_match()
    {
        Assert.Equal(-1, GpuMatcher.Match("Some GPU", 0x1234, Lhm));
        var two = new (string, string)[] { ("AMD Radeon A", "GpuAmd"), ("AMD Radeon B", "GpuAmd") };
        Assert.Equal(-1, GpuMatcher.Match("AMD Radeon Z", GpuMatcher.VendorAmd, two));
    }

    [Fact]
    public void Integrated_means_less_than_1GiB_of_dedicated_memory()
    {
        Assert.True(GpuMatcher.IsIntegrated(128UL << 20));
        Assert.False(GpuMatcher.IsIntegrated(6UL << 30));
    }
}

public class RunningStatsTests
{
    [Fact]
    public void Tracks_min_max_average_and_skips_nulls()
    {
        var s = new RunningStats();
        s.Add(60); s.Add(null); s.Add(80); s.Add(float.NaN);
        Assert.Equal(2, s.Count);
        Assert.Equal(80, s.Max);
        Assert.Equal(60, s.Min);
        Assert.Equal(70, s.Average);
    }

    [Fact]
    public void Empty_stats_have_no_values()
    {
        var s = new RunningStats();
        Assert.Null(s.Max);
        Assert.Null(s.Average);
    }
}
