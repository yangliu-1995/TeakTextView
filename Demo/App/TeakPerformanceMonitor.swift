import UIKit
import Darwin

@MainActor
final class TeakPerformanceMonitor: NSObject {
    var onUpdate: ((Double, Double) -> Void)?
    private var link: CADisplayLink?
    private var startTimestamp = 0.0
    private var frames = 0

    func start() {
        stop()
        startTimestamp = 0
        frames = 0
        let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        if startTimestamp == 0 { startTimestamp = sender.timestamp }
        frames += 1
        let interval = sender.timestamp - startTimestamp
        guard interval >= 0.5 else { return }
        let fps = Double(frames) / interval
        startTimestamp = sender.timestamp
        frames = 0
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS { onUpdate?(fps, Double(info.phys_footprint) / 1_048_576) }
    }
}
