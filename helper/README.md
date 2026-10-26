# SolHelper

Small C# (.NET 8) console app that does the hardware work Flutter cannot:
CPU/GPU stress tests and sensor readings. SolLapChecker starts it with
`Process.start` and reads **JSON lines from stdout**.

## Build

```powershell
.\helper\build.ps1          # Windows: publishes a self-contained single file to tools\SolHelper.exe
./helper/build.sh           # macOS/Linux cross-build (needs the .NET 8 SDK)
dotnet test helper/SolHelper.Tests   # unit tests for the pure logic (runs on any OS)
```

## Commands

| Command | Output |
|---|---|
| `SolHelper info` | one `info` line: admin / PawnIO status, CPU, GPUs, sensor availability |
| `SolHelper cpu-stress --duration 60 [--limit 95]` | `start`, a `sample` per second, `end` |
| `SolHelper gpu-stress --gpu <index> --duration 60 [--limit 95]` | same, for the GPU with that DXGI index |

Send `stop` on stdin (or close stdin) to end a test early. Every test is also stopped
automatically when any monitored temperature reaches the limit (95 °C by default),
when the temperature sensor stops responding, or when the test load fails. The helper
refuses to start a test at all if it cannot read the temperature.

Event shapes (`type` = `start | sample | warning | error | end | info`) are defined in
`SolHelper/Protocol.cs` and parsed by `lib/core/models/stress.dart`.

## Sensors need the PawnIO driver

LibreHardwareMonitorLib 0.9.5+ reads CPU temperatures/clocks through the signed
**PawnIO** driver (the older WinRing0 driver is blocked by Windows Defender). Without
PawnIO most Intel/AMD laptops expose no CPU temperature, and the stress tests will
refuse to run. `SolHelper info` reports `pawnIo: true/false`; the installer
(Phase 7) must install PawnIO (https://pawnio.eu).

## Throttling

`Logic/ThrottleDetector.cs`: a clock below 85% of its peak sustained value for 5
seconds in a row while fully loaded. If the part was ≥ 80 °C it is *thermal*
throttling; otherwise only a power/boost limit (normal on thin laptops).
