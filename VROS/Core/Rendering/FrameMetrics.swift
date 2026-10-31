import Foundation

struct FrameMetrics {
    var fps: Double = 0
    var cpuMilliseconds: Double = 0
    /// GPUStartTime/GPUEndTime are available only after a completed Metal command buffer.
    var gpuMilliseconds: Double?
    var renderScale: Float = 1
    var droppedFrames: Int = 0
}
