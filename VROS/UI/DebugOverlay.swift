import SwiftUI

struct DebugOverlay: View {
    let metrics: FrameMetrics
    let trackingStatus: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VR-OS 2.0 • Laboratório 3DoF").font(.headline)
            Text(trackingStatus)
            Text(String(format: "%.1f FPS • CPU %.2f ms • GPU %@", metrics.fps,
                        metrics.cpuMilliseconds,
                        metrics.gpuMilliseconds.map { String(format: "%.2f ms", $0) } ?? "—"))
                .monospacedDigit()
            Text(String(format: "Resolução %.0f%% • Frames descartados %d", metrics.renderScale * 100,
                        metrics.droppedFrames)).monospacedDigit()
            if let error { Text(error).foregroundStyle(.red) }
        }
        .font(.caption).padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}
