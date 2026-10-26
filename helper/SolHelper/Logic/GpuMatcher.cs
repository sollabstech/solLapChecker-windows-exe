using System.Text;

namespace SolHelper.Logic;

/// <summary>
/// Pairs a DXGI adapter (used to run the compute load) with the
/// LibreHardwareMonitor GPU (used to read its sensors); the two APIs name
/// the same card slightly differently.
/// </summary>
public static class GpuMatcher
{
    public const uint VendorNvidia = 0x10DE;
    public const uint VendorAmd = 0x1002;
    public const uint VendorIntel = 0x8086;

    /// <summary>Adapters with less than 1 GiB of dedicated VRAM share system memory: integrated.</summary>
    public static bool IsIntegrated(ulong dedicatedVideoMemoryBytes) =>
        dedicatedVideoMemoryBytes < 1UL << 30;

    public static string? LhmTypeFor(uint vendorId) => vendorId switch
    {
        VendorNvidia => "GpuNvidia",
        VendorAmd => "GpuAmd",
        VendorIntel => "GpuIntel",
        _ => null,
    };

    /// <summary>Index into <paramref name="lhmGpus"/> of the matching sensor hardware, or -1.</summary>
    public static int Match(string dxgiName, uint vendorId, IReadOnlyList<(string Name, string HardwareType)> lhmGpus)
    {
        var target = Normalize(dxgiName);

        for (var i = 0; i < lhmGpus.Count; i++)
        {
            var n = Normalize(lhmGpus[i].Name);
            if (n.Length > 0 && (n == target || target.Contains(n) || n.Contains(target))) return i;
        }

        // Same vendor, and only one candidate: unambiguous.
        var type = LhmTypeFor(vendorId);
        if (type is null) return -1;
        var sameVendor = Enumerable.Range(0, lhmGpus.Count).Where(i => lhmGpus[i].HardwareType == type).ToList();
        return sameVendor.Count == 1 ? sameVendor[0] : -1;
    }

    static string Normalize(string s)
    {
        var sb = new StringBuilder(s.Length);
        var t = s.ToLowerInvariant().Replace("(r)", "").Replace("(tm)", "");
        foreach (var c in t)
            if (char.IsLetterOrDigit(c)) sb.Append(c);
        return sb.ToString();
    }
}
