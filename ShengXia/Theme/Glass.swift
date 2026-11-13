import ShengXiaCore
import SwiftUI
import UIKit

struct SXGlass: ViewModifier {
    var radius: CGFloat
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: radius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: radius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                )
        }
    }
}

struct CircleGlass: ViewModifier {
    var active: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(active ? .regular.tint(SX.cinnabar).interactive() : .regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(active ? SX.cinnabar.opacity(0.8) : Color.white.opacity(0.28), lineWidth: 0.8))
        }
    }
}

struct CapsuleGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6))
        }
    }
}

struct SXGlassButton: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func sxGlass(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        modifier(SXGlass(radius: cornerRadius, interactive: interactive))
    }

    func sxCapsuleGlass() -> some View { modifier(CapsuleGlass()) }

    func sxGlassButton(prominent: Bool = false) -> some View { modifier(SXGlassButton(prominent: prominent)) }
}

struct SXBackground: View {
    var body: some View {
        LinearGradient(
            colors: [SX.paper, SX.paper.opacity(0.94), SX.cinnabar.opacity(0.14)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct SettingsButton: View {
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        Button { shell.showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .modifier(CircleGlass())
        .accessibilityLabel("设置")
    }
}

struct CoverThumb: View {
    @EnvironmentObject private var library: LibraryStore
    let track: Track?
    var side: CGFloat
    var radius: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    SX.cinnabar.opacity(0.18)
                    Image(systemName: "music.note").foregroundStyle(SX.cinnabar)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: path) {
            image = path.flatMap { UIImage(contentsOfFile: $0) }
        }
    }

    private var path: String? {
        guard let track else { return nil }
        return library.coverURL(for: track)?.path
    }
}

enum LinkOpener {
    static func open(_ track: Track) {
        guard let raw = track.sourceURL, let url = URL(string: raw) else { return }
        UIApplication.shared.open(url)
    }
}
