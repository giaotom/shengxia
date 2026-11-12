import SwiftUI

@main
struct ShengXiaApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var player: PlayerModel
    @StateObject private var importer: ImportController

    init() {
        let library = LibraryStore()
        _library = StateObject(wrappedValue: library)
        _player = StateObject(wrappedValue: PlayerModel(library: library))
        _importer = StateObject(wrappedValue: ImportController())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(importer)
        }
    }
}
