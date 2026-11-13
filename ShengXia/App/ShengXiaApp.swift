import SwiftUI

@main
struct ShengXiaApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var library: LibraryStore
    @StateObject private var player: PlayerModel
    @StateObject private var importer: ImportController
    @StateObject private var shell: ShellState

    init() {
        let settings = SettingsStore()
        let library = LibraryStore()
        let player = PlayerModel(library: library, settings: settings)
        let importer = ImportController(library: library, player: player, settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _library = StateObject(wrappedValue: library)
        _player = StateObject(wrappedValue: player)
        _importer = StateObject(wrappedValue: importer)
        _shell = StateObject(wrappedValue: ShellState())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(importer)
                .environmentObject(shell)
        }
    }
}
