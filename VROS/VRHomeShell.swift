import SwiftUI
import UIKit

/// Native implementation of the audited Home layout: a library with a left
/// rail above a persistent capsule dock. All input uses VRHomeLayout.
struct VRHomeShell: View {
    @ObservedObject var library: VRHomeLibrary
    let viewport: CGSize
    let windows: [VRHomeWindow]
    let cameraEnabled: Bool
    let motionAvailable: Bool
    let dwellDelay: CGFloat
    var showHUD = true
    var notice: String? = nil
    let onAction: (VRHomeAction) -> Void

    var body: some View {
        let canvas = VRHomeCanvas(viewport: viewport)
        ZStack(alignment: .topLeading) {
            if library.visible || library.quickSettings { libraryCard.onTapGesture {} }
            dockBackground
            ForEach(VRHomeLayout.targets(library, windows: windows)) { target in
                targetButton(target)
            }
        }
        .foregroundStyle(VRDS.Color.primary)
        .frame(width: 640, height: 420)
        .scaleEffect(canvas.scale)
        .position(x: viewport.width / 2, y: viewport.height / 2)
        .frame(width: viewport.width, height: viewport.height)
    }

    private var libraryCard: some View {
        let rect = VRHomeLayout.card
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(VRDS.Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(VRDS.Color.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            Text(library.quickSettings ? "Ajustes rápidos" : "Biblioteca")
                .font(.system(size: library.quickSettings ? 23 : 21, weight: .semibold))
                .frame(width: library.quickSettings ? 280 : 148, alignment: .leading)
                .position(x: library.quickSettings ? 177 : 100, y: 43)
            if library.quickSettings {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                    Text("Brilho  \(Int(UIScreen.main.brightness * 100))%")
                }.font(.system(size: 18)).position(x: 320, y: 270)
                Text(cameraEnabled ? "Câmera ligada" : "Modo sem câmera")
                    .font(.system(size: 12)).foregroundStyle(VRDS.Color.secondary)
                    .position(x: 320, y: 308)
            } else {
                Rectangle().fill(VRDS.Color.border).frame(width: 1, height: 206)
                    .position(x: 165, y: 177)
                let pages = library.pageCount(windowCount: windows.count)
                Text("\(min(library.page + 1, pages)) / \(pages)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(VRDS.Color.secondary)
                    .position(x: 390, y: 292)
                if (library.section == .windows && windows.isEmpty) ||
                    (library.section != .windows && library.entries.isEmpty) {
                    VStack(spacing: 12) {
                        Image(systemName: library.section == .windows ? "rectangle.on.rectangle" : "magnifyingglass")
                            .font(.system(size: 36, weight: .light))
                        Text(library.section == .windows ? "Nenhuma janela aberta" : "Nenhum resultado")
                            .font(.system(size: 19, weight: .medium))
                        Text(library.section == .windows ? "Abra um app na Biblioteca." : "Tente buscar outro nome.")
                            .font(.system(size: 14))
                    }.foregroundStyle(VRDS.Color.secondary)
                        .frame(width: 420).position(x: 390, y: 172)
                }
            }
        }
    }

    private var dockBackground: some View {
        let rect = VRHomeLayout.dock
        return ZStack(alignment: .topLeading) {
            Capsule().fill(LinearGradient(colors: [VRDS.Color.surfaceElevated, VRDS.Color.surface],
                startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(VRDS.Color.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            Rectangle().fill(VRDS.Color.border).frame(width: 1, height: 32).position(x: 277, y: 372)
            Rectangle().fill(VRDS.Color.border).frame(width: 1, height: 32).position(x: 532, y: 372)
            if let notice = notice {
                Text(notice).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(VRDS.Color.primary)
                    .frame(width: 600).position(x: 320, y: 328).allowsHitTesting(false)
            } else if showHUD { HStack(spacing: 5) {
                Circle().fill(motionAvailable ? VRDS.Color.success : VRDS.Color.secondary).frame(width: 4, height: 4)
                Text("VR-OS").font(.system(size: 11, weight: .semibold)).tracking(1)
                Text("·  Mira \(String(format: "%.1f", Double(dwellDelay))) s")
                    .font(.system(size: 11)).foregroundStyle(VRDS.Color.secondary)
            }.position(x: 320, y: 328).allowsHitTesting(false) }
        }
    }

    private func targetButton(_ target: VRHomeTarget) -> some View {
        let hovered = library.hovered == target.action.key
        return Button { onAction(target.action) } label: {
            targetLabel(target)
                .frame(width: target.rect.width, height: target.rect.height)
                .background(background(for: target, hovered: hovered),
                    in: RoundedRectangle(cornerRadius: target.style == .dock ? 24 : 16))
                .overlay(RoundedRectangle(cornerRadius: target.style == .dock ? 24 : 16)
                    .stroke(hovered ? VRDS.Color.primary.opacity(0.8) : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.title.isEmpty ? "Ajustes rápidos" : target.title)
        .position(x: target.rect.midX, y: target.rect.midY)
    }

    @ViewBuilder
    private func targetLabel(_ target: VRHomeTarget) -> some View {
        switch target.style {
        case .tile:
            VStack(spacing: 4) {
                Image(systemName: target.symbol)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(Color(vrHex: target.color))
                    .frame(width: 48, height: 42)
                    .background(Color(vrHex: target.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                Text(target.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if !target.detail.isEmpty {
                    Text(target.detail).font(.system(size: 9)).lineLimit(1)
                        .foregroundStyle(VRDS.Color.secondary)
                }
            }.padding(.horizontal, 4)
        case .rail:
            HStack(spacing: 9) {
                Image(systemName: target.symbol).frame(width: 19)
                Text(target.title).lineLimit(1)
                Spacer(minLength: 0)
            }.font(.system(size: 14, weight: target.selected ? .semibold : .regular))
                .padding(.horizontal, 10)
        case .dock:
            if target.action == .quick {
                VStack(spacing: 3) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        Text(timeline.date, format: .dateTime.hour().minute())
                            .font(.system(size: 17, weight: .semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100percent")
                        let level = UIDevice.current.batteryLevel
                        Text(level >= 0 ? "\(Int(level * 100))%" : "VR-OS")
                    }.font(.system(size: 9)).foregroundStyle(VRDS.Color.secondary)
                }
            } else {
                VStack(spacing: 3) {
                    Image(systemName: target.symbol).font(.system(size: 21, weight: .medium))
                        .foregroundStyle(target.action == .camera && cameraEnabled ? VRDS.Color.success : VRDS.Color.primary)
                    Text(target.title).font(.system(size: 8, weight: .medium)).lineLimit(1)
                }
            }
        case .pin:
            Image(systemName: target.symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(target.selected ? VRDS.Color.primary : VRDS.Color.secondary)
        case .control:
            HStack(spacing: 6) {
                Image(systemName: target.symbol)
                if target.action == .search || target.action == .sort {
                    Text(target.title).lineLimit(1).truncationMode(.tail)
                }
            }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 8)
        }
    }

    private func background(for target: VRHomeTarget, hovered: Bool) -> Color {
        if hovered { return VRDS.Color.surfacePressed }
        if target.selected || (target.action == .camera && cameraEnabled) { return VRDS.Color.surfacePressed.opacity(0.85) }
        if target.style == .tile || target.style == .control { return VRDS.Color.surfaceElevated }
        return .clear
    }
}

/// The default environment never requests a camera. It is deliberately quiet
/// behind the library and spatial windows.
struct VRHomeBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(vrHex: "050714"),
                        Color(vrHex: "0C1230"),
                        Color(vrHex: "070817")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(vrHex: "6E57FF").opacity(0.23),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: proxy.size.width * 0.9
                )

                Canvas { context, size in
                    for index in 0..<120 {
                        let x = CGFloat((index * 47 + 13) % 100) / 100 * size.width
                        let y = CGFloat((index * 73 + 19) % 76) / 100 * size.height
                        let radius: CGFloat = index % 17 == 0 ? 1.5 : 0.65
                        let star = CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: star),
                            with: .color(.white.opacity(index % 5 == 0 ? 0.78 : 0.34))
                        )
                    }

                    let horizon = size.height * 0.72
                    let neon = Color(vrHex: "63E7FF")
                    for index in 0..<9 {
                        let t = CGFloat(index + 1) / 9
                        let y = horizon + t * t * (size.height - horizon)
                        var horizontal = Path()
                        horizontal.move(to: CGPoint(x: 0, y: y))
                        horizontal.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(horizontal, with: .color(neon.opacity(0.16)), lineWidth: 0.7)
                    }
                    for index in -9...9 {
                        var vertical = Path()
                        let x = size.width / 2 + CGFloat(index) * size.width / 13
                        vertical.move(to: CGPoint(x: size.width / 2, y: horizon))
                        vertical.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(vertical, with: .color(neon.opacity(0.13)), lineWidth: 0.7)
                    }

                    var horizonLine = Path()
                    horizonLine.move(to: CGPoint(x: size.width * 0.08, y: horizon))
                    horizonLine.addLine(to: CGPoint(x: size.width * 0.92, y: horizon))
                    context.stroke(horizonLine, with: .color(neon.opacity(0.42)), lineWidth: 1)
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.25),
                        .clear,
                        .black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .allowsHitTesting(false)
    }
}
