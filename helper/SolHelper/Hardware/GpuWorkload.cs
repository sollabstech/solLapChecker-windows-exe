using System.Diagnostics;
using System.Runtime.InteropServices;
using Vortice.D3DCompiler;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace SolHelper.Hardware;

/// <summary>
/// Heavy ALU compute load on one GPU through a Direct3D 11 compute shader.
///
/// The work is submitted in short bursts (≈30 ms each) and the CPU waits for each
/// to finish. Keeping every dispatch well under Windows' 2 s watchdog (TDR) means a
/// slow or struggling GPU cannot hang the display driver, and a stop request is
/// honoured within a fraction of a second.
/// </summary>
sealed class GpuWorkload : IDisposable
{
    const int ThreadsPerGroup = 256;
    const int Groups = 8192; // 2M threads per dispatch
    const double TargetDispatchMs = 30;

    const string Shader = @"
RWStructuredBuffer<float> Output : register(u0);
cbuffer Params : register(b0) { uint iterations; float seed; uint pad0; uint pad1; };

[numthreads(256, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float a = id.x * 0.00001f + seed;
    float b = 1.0001f;
    float c = 0.5f;
    [loop] for (uint i = 0; i < iterations; i++)
    {
        a = mad(a, b, c);
        b = sin(a) * 0.5f + 1.0f;
        c = cos(b) + a * 0.0001f;
        a = sqrt(abs(a)) + b * c;
    }
    Output[id.x] = a + b + c;
}";

    readonly IDXGIAdapter1 _adapter;
    ID3D11Device? _device;
    ID3D11DeviceContext? _context;
    ID3D11ComputeShader? _shader;
    ID3D11Buffer? _output;
    ID3D11UnorderedAccessView? _uav;
    ID3D11Buffer? _params;
    ID3D11Query? _done;

    Thread? _thread;
    volatile bool _stop;
    uint _iterations = 32;

    public GpuWorkload(IDXGIAdapter1 adapter) => _adapter = adapter;

    /// <summary>Set if the load thread failed (e.g. device removed).</summary>
    public string? Failure { get; private set; }

    public double LastDispatchMs { get; private set; }

    /// <summary>Creates the device and compiles the shader; throws with a clear message on failure.</summary>
    public void Initialize()
    {
        var hr = Vortice.Direct3D11.D3D11.D3D11CreateDevice(
            _adapter,
            DriverType.Unknown,
            DeviceCreationFlags.None,
            new[] { FeatureLevel.Level_11_0 },
            out _device,
            out _context);
        if (hr.Failure || _device is null || _context is null)
            throw new InvalidOperationException($"Could not create a Direct3D 11 device ({hr}).");

        var compile = Compiler.Compile(Shader, "main", "gpu_stress.hlsl", "cs_5_0", out var blob, out var errors);
        if (compile.Failure || blob is null)
            throw new InvalidOperationException($"Shader compilation failed: {errors?.AsString()}");
        using (blob) _shader = _device.CreateComputeShader(blob.AsBytes());

        var count = ThreadsPerGroup * Groups;
        _output = _device.CreateBuffer(new BufferDescription
        {
            ByteWidth = (uint)(count * sizeof(float)),
            Usage = ResourceUsage.Default,
            BindFlags = BindFlags.UnorderedAccess,
            MiscFlags = ResourceOptionFlags.BufferStructured,
            StructureByteStride = sizeof(float),
        });
        _uav = _device.CreateUnorderedAccessView(_output, new UnorderedAccessViewDescription
        {
            Format = Format.Unknown,
            ViewDimension = UnorderedAccessViewDimension.Buffer,
            Buffer = new BufferUnorderedAccessView { FirstElement = 0, NumElements = (uint)count },
        });
        _params = _device.CreateBuffer(new BufferDescription(16, BindFlags.ConstantBuffer, ResourceUsage.Default));
        _done = _device.CreateQuery(new QueryDescription(QueryType.Event, QueryFlags.None));
    }

    public void Start()
    {
        _thread = new Thread(Loop) { IsBackground = true, Name = "gpu-stress", Priority = ThreadPriority.BelowNormal };
        _thread.Start();
    }

    void Loop()
    {
        var ctx = _context!;
        var sw = new Stopwatch();
        var seed = 0.5f;

        try
        {
            ctx.CSSetShader(_shader);
            ctx.CSSetUnorderedAccessView(0, _uav);
            ctx.CSSetConstantBuffer(0, _params);

            while (!_stop)
            {
                var p = new[] { _iterations, BitConverter.SingleToUInt32Bits(seed), 0u, 0u };
                ctx.UpdateSubresource(p, _params!);

                sw.Restart();
                ctx.Dispatch(Groups, 1, 1);
                ctx.End(_done!);
                ctx.Flush();

                // Wait for the GPU to finish this burst (yielding the CPU while we wait).
                while (!_stop && !EventSignalled(ctx)) Thread.Sleep(1);
                sw.Stop();

                LastDispatchMs = sw.Elapsed.TotalMilliseconds;
                Adapt(LastDispatchMs);
                seed += 0.001f;
                if (seed > 2f) seed = 0.5f;
            }
        }
        catch (Exception e)
        {
            Failure = e.Message;
        }
    }

    bool EventSignalled(ID3D11DeviceContext ctx)
    {
        return ctx.GetData(_done!, out int signalled) && signalled != 0;
    }

    /// <summary>Scales iterations so one dispatch lasts about <see cref="TargetDispatchMs"/>.</summary>
    void Adapt(double lastMs)
    {
        if (lastMs <= 0) return;
        var factor = TargetDispatchMs / lastMs;
        factor = Math.Clamp(factor, 0.5, 2.0);
        _iterations = (uint)Math.Clamp(_iterations * factor, 8, 1_000_000);
    }

    public void Stop()
    {
        _stop = true;
        _thread?.Join(3000);
        _thread = null;
    }

    public void Dispose()
    {
        Stop();
        _done?.Dispose();
        _params?.Dispose();
        _uav?.Dispose();
        _output?.Dispose();
        _shader?.Dispose();
        _context?.Dispose();
        _device?.Dispose();
    }
}
