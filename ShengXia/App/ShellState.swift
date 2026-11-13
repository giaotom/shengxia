import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case extract, library, playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extract: return "提取"
        case .library: return "资料库"
        case .playlists: return "歌单"
        }
    }

    var symbol: String {
        switch self {
        case .extract: return "link"
        case .library: return "music.note.list"
        case .playlists: return "rectangle.stack.fill"
        }
    }
}

@MainActor
final class ShellState: ObservableObject {
    @Published var tab: AppTab = .extract
    @Published var showPlayer = false
    @Published var showSettings = false
}
