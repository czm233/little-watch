import Darwin
import Foundation

actor SystemMetricsMonitor {
    private var previousCPUTicks: [UInt64]?
    private var latest = SystemMetricsSnapshot.empty

    func sample() -> SystemMetricsSnapshot {
        let cpu = sampleCPU() ?? latest.cpuUsagePercent
        let memory = sampleMemory() ?? latest.memoryUsagePercent
        let disk = sampleDisk()

        latest = SystemMetricsSnapshot(
            cpuUsagePercent: cpu,
            memoryUsagePercent: memory,
            diskUsagePercent: disk?.usagePercent ?? latest.diskUsagePercent,
            diskFreeBytes: disk?.freeBytes ?? latest.diskFreeBytes,
            updatedAt: Date()
        )
        return latest
    }

    private func sampleCPU() -> Double? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var totals = [UInt64](repeating: 0, count: Int(CPU_STATE_MAX))
        for cpu in 0..<Int(cpuCount) {
            for state in 0..<Int(CPU_STATE_MAX) {
                totals[state] += UInt64(cpuInfo[cpu * Int(CPU_STATE_MAX) + state])
            }
        }

        guard let previousCPUTicks else {
            self.previousCPUTicks = totals
            return nil
        }
        self.previousCPUTicks = totals

        let deltas = zip(totals, previousCPUTicks).map { current, previous in
            current >= previous ? current - previous : 0
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        return min(max(Double(total - idle) / Double(total) * 100, 0), 100)
    }

    private func sampleMemory() -> Double? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var rawPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &rawPageSize) == KERN_SUCCESS else { return nil }
        let pageSize = Double(rawPageSize)
        let usedPages = Double(statistics.active_count)
            + Double(statistics.wire_count)
            + Double(statistics.compressor_page_count)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return nil }
        return min(max(usedPages * pageSize / totalBytes * 100, 0), 100)
    }

    private func sampleDisk() -> (usagePercent: Double, freeBytes: Int64)? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/df")
        process.arguments = ["-k", "/"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return Self.parseDiskUsage(output: text)
        } catch {
            return nil
        }
    }

    nonisolated static func parseDiskUsage(output: String) -> (usagePercent: Double, freeBytes: Int64)? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return nil }
        let columns = lines[1].split(whereSeparator: \.isWhitespace)
        guard
            columns.count >= 5,
            let availableKilobytes = Int64(columns[3]),
            let usagePercent = Double(columns[4].trimmingCharacters(in: CharacterSet(charactersIn: "%")))
        else {
            return nil
        }

        return (usagePercent, availableKilobytes * 1024)
    }
}
