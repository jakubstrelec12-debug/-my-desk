import Foundation
import Darwin
import IOKit.ps

final class SystemMetrics {
    private let host = mach_host_self()
    deinit { mach_port_deallocate(mach_task_self_, host) }
    private var previousCPU: [UInt64]?
    func sample() -> MetricSample {
        var sample = MetricSample()
        sample.memory = memoryUsage()
        sample.cpu = cpuUsage()
        let volume = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        if let total = volume?.volumeTotalCapacity, total > 0, let free = volume?.volumeAvailableCapacityForImportantUsage {
            sample.disk = max(0, min(1, 1 - Double(free) / Double(total)))
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      let current = d[kIOPSCurrentCapacityKey] as? NSNumber,
                      let maximum = d[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 else { continue }
                sample.battery = max(0, min(1, current.doubleValue / maximum.doubleValue))
                sample.charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                break
            }
        }
        return sample
    }
    private func memoryUsage() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let pages = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return min(1, max(0, pages * Double(pageSize) / Double(ProcessInfo.processInfo.physicalMemory)))
    }
    private func cpuUsage() -> Double? {
        var stats = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = [stats.cpu_ticks.0, stats.cpu_ticks.1, stats.cpu_ticks.2, stats.cpu_ticks.3].map(UInt64.init)
        defer { previousCPU = ticks }
        guard let previousCPU else { return nil }
        let deltas = zip(ticks, previousCPU).map { ($0.0 &- $0.1) & 0xffffffff }
        let total = deltas.reduce(0, +)
        return total > 0 ? max(0, min(1, 1 - Double(deltas[2]) / Double(total))) : nil
    }
    static func hardwareModel() -> String {
        var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Tento Mac" }
        var chars = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &chars, &size, nil, 0) == 0 else { return "Tento Mac" }
        let model = String(cString: chars)
        return model == "Mac14,2" ? "MacBook Air M2" : model
    }
}
