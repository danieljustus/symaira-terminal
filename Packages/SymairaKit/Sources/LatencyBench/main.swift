import Foundation
import GhosttyBridge
import TerminalCore

enum BenchError: Error {
    case surfaceCreationFailed
    case timeout
}

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func add(_ n: Int) {
        lock.lock()
        _value += n
        lock.unlock()
    }
}

@MainActor
final class LatencyBench {
    let engine = GhosttyEngine()
    var results: [String: Double] = [:]

    func run() async throws {
        print("=== Symaira Terminal M1 Latency Benchmark ===")
        print("Engine: \(engine.engineDescription)\n")

        try await measureKeypressToRender()
        try await measureThroughput()
        try await measureMemory()

        print("\n=== Results ===")
        for (name, value) in results.sorted(by: { $0.key < $1.key }) {
            print("  \(name): \(String(format: "%.2f", value))")
        }
    }

    private func measureKeypressToRender() async throws {
        let surface = try engine.makeSurface(configuration: .init())
        guard let ghostty = surface as? GhosttySurfaceController else {
            throw BenchError.surfaceCreationFailed
        }

        var latencies: [Double] = []
        let iterations = 50

        for i in 0..<iterations {
            let marker = "BENCH_\(i)_\(UUID().uuidString.prefix(8))"
            let startTime = DispatchTime.now()
            ghostty.sendText("echo \(marker)\n")
            try await Task.sleep(for: .milliseconds(50))
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            latencies.append(elapsed)
        }

        ghostty.close()

        let avg = latencies.reduce(0, +) / Double(latencies.count)
        let sorted = latencies.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let p99 = sorted[Int(Double(sorted.count) * 0.99)]

        results["keypress_to_render_avg_ms"] = avg
        results["keypress_to_render_p50_ms"] = p50
        results["keypress_to_render_p95_ms"] = p95
        results["keypress_to_render_p99_ms"] = p99

        print("Keypress-to-render (\(iterations) iterations):")
        print("  avg=\(String(format: "%.2f", avg))ms  p50=\(String(format: "%.2f", p50))ms"
            + "  p95=\(String(format: "%.2f", p95))ms  p99=\(String(format: "%.2f", p99))ms")
        print("  target: ≤ 8ms @ 120Hz (iTerm2 baseline)")
    }

    private func measureThroughput() async throws {
        let surface = try engine.makeSurface(configuration: .init(command: "cat /dev/urandom | head -c 52428800"))
        guard let ghostty = surface as? GhosttySurfaceController else {
            throw BenchError.surfaceCreationFailed
        }

        let startTime = DispatchTime.now()
        let bytesReceived = ThreadSafeCounter()
        let tap: @Sendable ([UInt8]) -> Void = { bytes in
            bytesReceived.add(bytes.count)
        }
        ghostty.outputTap = tap

        try await Task.sleep(for: .seconds(10))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        ghostty.close()

        let throughputMBs = Double(bytesReceived.value) / (1024 * 1024) / elapsed
        results["throughput_mb_per_sec"] = throughputMBs
        results["throughput_total_bytes"] = Double(bytesReceived.value)

        print("\nThroughput (50MB cat /dev/urandom, \(String(format: "%.1f", elapsed))s):")
        print("  \(String(format: "%.1f", throughputMBs)) MB/s (\(bytesReceived.value) bytes received)")
        print("  target: no frame drops, no UI lock")
    }

    private func measureMemory() async throws {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let rssBytes = info.resident_size
        let rssMB = Double(rssBytes) / (1024 * 1024)
        results["memory_rss_mb"] = rssMB

        print("\nMemory (idle, single pane):")
        print("  RSS: \(String(format: "%.1f", rssMB)) MB")
        print("  target: < 200 MB with 4 panes")
    }
}

let bench = LatencyBench()
Task { @MainActor in
    do {
        try await bench.run()
        print("\nBENCHMARK COMPLETE")
    } catch {
        print("BENCHMARK FAILED: \(error)")
    }
    exit(0)
}
RunLoop.main.run()
