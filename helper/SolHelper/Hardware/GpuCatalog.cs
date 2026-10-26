using SolHelper.Logic;
using Vortice.DXGI;

namespace SolHelper.Hardware;

/// <summary>A hardware GPU as seen by DXGI (the API that will run the compute load).</summary>
sealed record GpuAdapter(int Index, string Name, uint VendorId, ulong DedicatedBytes)
{
    public bool Integrated => GpuMatcher.IsIntegrated(DedicatedBytes);
}

static class GpuCatalog
{
    /// <summary>All non-software adapters, in DXGI enumeration order.</summary>
    public static List<GpuAdapter> Enumerate()
    {
        var result = new List<GpuAdapter>();
        using var factory = DXGI.CreateDXGIFactory1<IDXGIFactory1>();
        for (uint i = 0; factory.EnumAdapters1(i, out IDXGIAdapter1? adapter).Success; i++)
        {
            using (adapter)
            {
                var d = adapter.Description1;
                if ((d.Flags & AdapterFlags.Software) != 0) continue; // "Microsoft Basic Render Driver"
                result.Add(new GpuAdapter((int)i, d.Description.Trim(), d.VendorId, (ulong)d.DedicatedVideoMemory));
            }
        }
        return result;
    }

    /// <summary>Opens the DXGI adapter with the given enumeration index.</summary>
    public static IDXGIAdapter1 Open(int index)
    {
        using var factory = DXGI.CreateDXGIFactory1<IDXGIFactory1>();
        if (!factory.EnumAdapters1((uint)index, out IDXGIAdapter1? adapter).Success)
            throw new InvalidOperationException($"No GPU with index {index}.");
        return adapter;
    }
}
