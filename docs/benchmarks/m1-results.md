# M1 Benchmark Results

## Environment

- **Date**: 2026-06-10
- **Engine**: libghostty (libghostty-spm 1.2.4)
- **Machine**: Apple Silicon (ARM64)
- **macOS**: 14.x+
- **Display**: 120 Hz

## Keypress-to-Render Latency

**Target**: ≤ 8ms @ 120 Hz (iTerm2 baseline)

| Metric | Result | Status |
|--------|--------|--------|
| Average | TBD ms | ⏳ |
| P50 | TBD ms | ⏳ |
| P95 | TBD ms | ⏳ |
| P99 | TBD ms | ⏳ |

**Method**: 50 iterations of `echo BENCH_<i>_<uuid>` with timing measurement.

**How to run**:
```bash
cd Packages/SymairaKit
swift run LatencyBench
```

## Throughput

**Target**: No frame drops, no UI lock during high-throughput output

| Metric | Result | Status |
|--------|--------|--------|
| Throughput | TBD MB/s | ⏳ |
| Total bytes | TBD | ⏳ |

**Method**: `cat /dev/urandom | head -c 50MB` with output tap measurement.

## Memory Usage

**Target**: < 200 MB RSS with 4 panes idle

| Metric | Result | Status |
|--------|--------|--------|
| RSS (single pane) | TBD MB | ⏳ |
| RSS (4 panes) | TBD MB | ⏳ |

**Method**: `task_info()` with `TASK_VM_INFO` flavor.

## Notes

- Benchmarks measure GhosttyKit rendering pipeline only
- UI frame drops measured via Instruments Time Profiler (manual verification)
- Memory includes GhosttyKit + PTY session overhead
- Results will be updated after first benchmark run on target hardware

## Updating Results

After running benchmarks, update the TBD values above:
```bash
cd Packages/SymairaKit
swift run LatencyBench 2>&1 | tee ../../docs/benchmarks/m1-output.log
```

Then copy the values from the output to this file.
