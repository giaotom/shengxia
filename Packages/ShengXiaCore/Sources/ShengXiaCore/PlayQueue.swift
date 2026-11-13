import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    public var title: String {
        switch self {
        case .off: return "不循环"
        case .all: return "列表循环"
        case .one: return "单曲循环"
        }
    }

    public var symbol: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

public struct PlayQueue: Equatable, Sendable {
    public private(set) var items: [UUID] = []
    public private(set) var currentIndex: Int?
    public private(set) var context: [UUID] = []
    public private(set) var isShuffled = false

    public init() {}

    public var current: UUID? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public var upcoming: [UUID] {
        guard let currentIndex else { return items }
        return Array(items.dropFirst(currentIndex + 1))
    }

    public func nextIndex(repeatMode: RepeatMode, automatic: Bool) -> Int? {
        guard let currentIndex, !items.isEmpty else { return items.isEmpty ? nil : 0 }
        if automatic && repeatMode == .one { return currentIndex }
        let next = currentIndex + 1
        if next < items.count { return next }
        return repeatMode == .off ? nil : 0
    }

    public func previousIndex(repeatMode: RepeatMode) -> Int? {
        guard let currentIndex, !items.isEmpty else { return nil }
        if currentIndex > 0 { return currentIndex - 1 }
        return repeatMode == .all ? items.count - 1 : nil
    }

    public mutating func load<G: RandomNumberGenerator>(
        _ ids: [UUID],
        startAt start: UUID?,
        shuffle: Bool,
        using rng: inout G
    ) {
        context = uniqued(ids)
        isShuffled = shuffle
        let first = start.flatMap { id in context.contains(id) ? id : nil }
        if shuffle {
            let rest = context.filter { $0 != first }.shuffled(using: &rng)
            items = (first.map { [$0] } ?? []) + rest
            currentIndex = items.isEmpty ? nil : 0
        } else {
            items = context
            currentIndex = first.flatMap { items.firstIndex(of: $0) } ?? (items.isEmpty ? nil : 0)
        }
    }

    public mutating func load(_ ids: [UUID], startAt start: UUID?, shuffle: Bool) {
        var rng = SystemRandomNumberGenerator()
        load(ids, startAt: start, shuffle: shuffle, using: &rng)
    }

    public mutating func setShuffle<G: RandomNumberGenerator>(_ on: Bool, using rng: inout G) {
        guard on != isShuffled else { return }
        isShuffled = on
        let currentID = current
        let extras = items.filter { !context.contains($0) }
        if on {
            let rest = uniqued(context + extras).filter { $0 != currentID }.shuffled(using: &rng)
            items = (currentID.map { [$0] } ?? []) + rest
            currentIndex = items.isEmpty ? nil : 0
        } else {
            items = uniqued(context + extras)
            currentIndex = currentID.flatMap { items.firstIndex(of: $0) } ?? (items.isEmpty ? nil : 0)
        }
    }

    public mutating func setShuffle(_ on: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(on, using: &rng)
    }

    public mutating func jump(to index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }

    public mutating func jump(toID id: UUID) {
        if let index = items.firstIndex(of: id) { currentIndex = index }
    }

    public mutating func playNext(_ id: UUID) {
        guard let currentIndex else {
            items = [id]
            self.currentIndex = 0
            return
        }
        if items[currentIndex] == id { return }
        if let existing = items.firstIndex(of: id) {
            items.remove(at: existing)
            if existing < currentIndex { self.currentIndex = currentIndex - 1 }
        }
        items.insert(id, at: (self.currentIndex ?? 0) + 1)
    }

    public mutating func append(_ id: UUID) {
        guard current != id else { return }
        if let existing = items.firstIndex(of: id), let currentIndex, existing > currentIndex {
            items.remove(at: existing)
        } else if let existing = items.firstIndex(of: id), let currentIndex, existing < currentIndex {
            items.remove(at: existing)
            self.currentIndex = currentIndex - 1
        }
        items.append(id)
        if currentIndex == nil { currentIndex = 0 }
    }

    public mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (currentIndex ?? -1) + 1
        var upcoming = self.upcoming
        upcoming.moveElements(fromOffsets: source, toOffset: destination)
        items = Array(items.prefix(base)) + upcoming
    }

    public mutating func removeUpcoming(atOffsets offsets: IndexSet) {
        let base = (currentIndex ?? -1) + 1
        for offset in offsets.sorted(by: >) {
            let index = base + offset
            if items.indices.contains(index) { items.remove(at: index) }
        }
    }

    public mutating func clearUpcoming() {
        guard let currentIndex else {
            items = []
            return
        }
        items = Array(items.prefix(currentIndex + 1))
    }

    @discardableResult
    public mutating func retain(_ live: Set<UUID>) -> Bool {
        let currentID = current
        let oldIndex = currentIndex
        let removedCurrent = currentID.map { !live.contains($0) } ?? false
        var keptCurrent: Int?
        var successor: Int?
        var kept: [UUID] = []
        for (index, id) in items.enumerated() where live.contains(id) {
            if let currentID, id == currentID { keptCurrent = kept.count }
            if successor == nil, let oldIndex, index > oldIndex { successor = kept.count }
            kept.append(id)
        }
        items = kept
        context = context.filter(live.contains)
        if removedCurrent {
            currentIndex = successor
        } else {
            currentIndex = currentID == nil ? nil : keptCurrent
        }
        return removedCurrent
    }

    private func uniqued(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
