import Foundation

/// Where one piece of small decor (a plant, a lamp, books) sits: on top
/// of a piece of furniture, or on the floor beside it.
struct SurfaceSpot: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// The small decor item.
    var itemID: UUID
    /// The furniture it stands on. Nil for the floor (a big plant).
    var hostID: UUID?
    /// From the host's left end to the piece's middle, seen from the front, in cm.
    var offsetCm: Double
    /// Where it stands, for pieces on the floor (room cm). Nil means "next
    /// to the furniture", wherever the screen puts it.
    var floorX: Double? = nil
    var floorY: Double? = nil
}

/// Where a piece on a surface is on the floor plan, and back.
enum SurfacePlacement {
    /// Unit vector from the host's left end to its right end, as seen by
    /// someone standing in front of it.
    static func rightward(_ rotation: Int) -> Point2D {
        let f = Facing.front(rotation)
        return Point2D(x: f.y, y: -f.x)
    }

    /// The plan point of a piece `offset` cm from the host's left end.
    static func point(offset: Double, on host: PlacedItem) -> Point2D {
        let r = rightward(host.placement.rotation)
        let along = offset - host.item.width / 2
        return Point2D(x: host.center.x + r.x * along, y: host.center.y + r.y * along)
    }

    /// The offset along the host for a plan point, kept on the host.
    static func offset(of p: Point2D, on host: PlacedItem, pieceWidth: Double) -> Double {
        let r = rightward(host.placement.rotation)
        let along = (p.x - host.center.x) * r.x + (p.y - host.center.y) * r.y + host.item.width / 2
        let half = min(pieceWidth / 2, host.item.width / 2)
        return min(max(along, half), host.item.width - half)
    }
}

/// A piece of small decor, as the planner sees it.
struct DecorPiece: Sendable, Identifiable {
    var id: UUID
    var type: ItemType
    var name: String
    var width: Double
    var depth: Double
    var height: Double
    var color: RGB?
    /// For lamps: how warm or cool the light is, if known.
    var light: LightWarmth? = nil

    /// The color family it brings to a group. A lamp's glow matters more
    /// than its shade's color: a warm-white lamp warms what's around it.
    var tone: RGB.Tone? { light?.tone ?? color?.tone }
}

/// A piece of furniture with a top that decor can stand on.
struct DecorSurface: Sendable, Identifiable {
    var id: UUID
    var type: ItemType
    var name: String
    var width: Double
    var depth: Double
    var height: Double

    /// A low table is a coffee table.
    var isCoffeeTable: Bool { type == .table && height < 55 }

    /// Room to leave at each end and between pieces.
    static let margin = 4.0
    static let gap = 6.0
}

struct SmallDecorSuggestion: Identifiable, Sendable {
    var id: String { label }
    var label: String
    var detail: String
    var spots: [SurfaceSpot]
    /// Pieces with nowhere to go (no fitting surface).
    var leftOut: [UUID]
}

/// Suggests where small decor goes: monitors and desk storage on the desk,
/// lamps at the end of a side table, desk, or dresser, books on shelves,
/// and so on. Offers a tidy version, a spread-out version, and (when the
/// pieces have photos) one that groups pieces of the same color family.
enum SmallDecorPlanner {
    /// Hosts that suit each kind of piece, best first. "coffeeTable" and
    /// "sideTable" are both tables, told apart by height.
    enum Host: Equatable { case desk, coffeeTable, sideTable, dresser, shelf, tvStand }

    static func hosts(for type: ItemType) -> [Host] {
        switch type {
        case .monitor: return [.desk, .sideTable]
        case .deskStorage: return [.desk, .shelf, .dresser]
        case .tableLamp: return [.sideTable, .desk, .dresser, .tvStand]
        case .books: return [.shelf, .coffeeTable, .desk, .dresser, .tvStand]
        case .plant: return [.shelf, .dresser, .tvStand, .sideTable, .coffeeTable, .desk]
        case .vase: return [.coffeeTable, .sideTable, .dresser, .tvStand, .shelf]
        case .tableClock: return [.dresser, .shelf, .desk, .tvStand, .sideTable]
        case .candle: return [.coffeeTable, .dresser, .tvStand, .shelf, .sideTable]
        default: return [.shelf, .dresser, .sideTable, .tvStand, .coffeeTable, .desk]
        }
    }

    static func host(_ surface: DecorSurface) -> Host? {
        switch surface.type {
        case .desk: return .desk
        case .table: return surface.isCoffeeTable ? .coffeeTable : .sideTable
        case .dresser: return .dresser
        case .shelf: return .shelf
        case .tvStand: return .tvStand
        default: return nil
        }
    }

    /// Pieces that work only in one kind of spot and ignore the style idea.
    static func isFunctional(_ type: ItemType) -> Bool { type == .monitor || type == .deskStorage }

    /// A plant this tall stands on the floor instead.
    static let floorPlantHeight = 70.0

    static func suggest(pieces: [DecorPiece], surfaces: [DecorSurface]) -> [SmallDecorSuggestion] {
        guard !pieces.isEmpty else { return [] }
        var results: [SmallDecorSuggestion] = [
            plan(pieces, surfaces, label: "Where each works best",
                 detail: "Each piece on the surface that suits it most: monitors on the desk, lamps at the end of a table, books on the shelf.",
                 choose: { _, options, _ in options.first }),
            plan(pieces, surfaces, label: "Spread out",
                 detail: "Shares the pieces across your surfaces so none looks cluttered.",
                 choose: { _, options, load in options.min { (load[$0.id] ?? 0) < (load[$1.id] ?? 0) } }),
        ]
        // Color groups need at least two pieces with known colors (or a
        // lamp's known glow).
        let toned = pieces.filter { $0.tone != nil }
        if toned.count >= 2 {
            results.append(colorGroups(pieces, surfaces))
        }
        // More ideas: each piece goes on a surface picked at random from the
        // ones that suit it, the same way every time for the same room.
        for n in 1...4 {
            var rng = SeededRandom(seed: UInt64(n) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(pieces.count))
            results.append(plan(pieces, surfaces, label: n == 1 ? "Mix it up" : "Mix it up \(n)",
                                detail: "A different mix: each piece on another surface that suits it.",
                                choose: { _, options, _ in options.isEmpty ? nil : options[Int(rng.next() % UInt64(options.count))] }))
        }
        // The same surfaces, arranged differently on each: flipped left to
        // right, and gathered in the middle.
        if let base = results.first {
            results.append(SmallDecorSuggestion(
                label: "Flipped", detail: "The first idea mirrored: what was on the left of each surface goes on the right.",
                spots: base.spots.map { spot in
                    guard let hostID = spot.hostID, let s = surfaces.first(where: { $0.id == hostID }) else { return spot }
                    var flipped = spot
                    flipped.offsetCm = s.width - spot.offsetCm
                    return flipped
                }, leftOut: base.leftOut))
            results.append(centered(base, pieces: pieces, surfaces: surfaces))
        }
        var unique: [SmallDecorSuggestion] = []
        for r in results where !unique.contains(where: { same($0.spots, r.spots) }) { unique.append(r) }
        return unique
    }

    /// Places pieces one by one, biggest first; `choose` picks a surface
    /// from the ones with room, given how many pieces each already holds.
    static func plan(
        _ pieces: [DecorPiece], _ surfaces: [DecorSurface], label: String, detail: String,
        choose: (DecorPiece, [DecorSurface], [UUID: Int]) -> DecorSurface?
    ) -> SmallDecorSuggestion {
        var assigned: [UUID: [DecorPiece]] = [:]
        var floor: [DecorPiece] = []
        var leftOut: [UUID] = []
        // Functional pieces first so they get their spot, then the bigger ones.
        let order = pieces.sorted {
            isFunctional($0.type) != isFunctional($1.type) ? isFunctional($0.type) : $0.width > $1.width
        }
        for piece in order {
            if piece.type == .plant, piece.height >= floorPlantHeight { floor.append(piece); continue }
            let options = candidates(for: piece, surfaces: surfaces, assigned: assigned)
            let load = assigned.mapValues(\.count)
            let usual = options.first.flatMap(host) == hosts(for: piece.type).first
            let pick = isFunctional(piece.type) && usual ? options.first : choose(piece, options, load)
            if let pick { assigned[pick.id, default: []].append(piece) } else { leftOut.append(piece.id) }
        }
        return SmallDecorSuggestion(label: label, detail: detail, spots: spots(assigned, surfaces: surfaces, floor: floor), leftOut: leftOut)
    }

    /// Groups pieces by color family (warm, cool, neutral) and gives each
    /// family its own surface, like a small styled corner. A lamp joins the
    /// family of its light, so a warm lamp lights up the warm pieces.
    static func colorGroups(_ pieces: [DecorPiece], _ surfaces: [DecorSurface]) -> SmallDecorSuggestion {
        var assigned: [UUID: [DecorPiece]] = [:]
        var floor: [DecorPiece] = []
        var leftOut: [UUID] = []
        var familyHost: [RGB.Tone: UUID] = [:]
        let order = pieces.sorted {
            isFunctional($0.type) != isFunctional($1.type) ? isFunctional($0.type) : $0.width > $1.width
        }
        for piece in order {
            if piece.type == .plant, piece.height >= floorPlantHeight { floor.append(piece); continue }
            let options = candidates(for: piece, surfaces: surfaces, assigned: assigned)
            guard !options.isEmpty else { leftOut.append(piece.id); continue }
            if isFunctional(piece.type) {
                assigned[options[0].id, default: []].append(piece)
                continue
            }
            let tone = piece.tone ?? .neutral
            let pick: DecorSurface
            if let hostID = familyHost[tone], let same = options.first(where: { $0.id == hostID }) {
                pick = same
            } else {
                // A surface no other family has claimed, if there is one.
                let claimed = Set(familyHost.values)
                pick = options.first { !claimed.contains($0.id) } ?? options[0]
                if familyHost[tone] == nil { familyHost[tone] = pick.id }
            }
            assigned[pick.id, default: []].append(piece)
        }
        return SmallDecorSuggestion(
            label: "Color groups",
            detail: "Puts pieces of the same color family together, so each surface has its own little matching group. Lamps join the group that suits their light.",
            spots: spots(assigned, surfaces: surfaces, floor: floor), leftOut: leftOut
        )
    }

    /// Surfaces that suit the piece and still have room for it, best first.
    static func candidates(for piece: DecorPiece, surfaces: [DecorSurface], assigned: [UUID: [DecorPiece]]) -> [DecorSurface] {
        let wanted = hosts(for: piece.type)
        let roomy = surfaces.filter { s in
            host(s) != nil && piece.depth <= s.depth + 2 && fits(assigned[s.id, default: []] + [piece], on: s)
        }
        let suited = roomy
            .filter { wanted.contains(host($0)!) }
            .sorted { a, b in
                let ra = wanted.firstIndex(of: host(a)!) ?? 99, rb = wanted.firstIndex(of: host(b)!) ?? 99
                return ra != rb ? ra < rb : a.width > b.width
            }
        // Nothing usual (a monitor with no desk): any top with room will do.
        return suited.isEmpty ? roomy.sorted { $0.width > $1.width } : suited
    }

    static func fits(_ pieces: [DecorPiece], on surface: DecorSurface) -> Bool {
        let used = pieces.reduce(0) { $0 + $1.width } + DecorSurface.gap * Double(max(pieces.count - 1, 0))
        return used <= surface.width - 2 * DecorSurface.margin
    }

    /// Where each piece sits along its surface: a lamp at the left end, a
    /// monitor in the middle, the rest from the right end inward, tallest
    /// first, which gives the classic stepped look.
    static func arrange(_ pieces: [DecorPiece], on surface: DecorSurface) -> [UUID: Double] {
        let lamps = pieces.filter { $0.type == .tableLamp }
        let middle = pieces.filter { $0.type == .monitor }
        let rest = pieces.filter { $0.type != .tableLamp && $0.type != .monitor }.sorted { $0.height > $1.height }
        var result: [UUID: Double] = [:]
        var left = DecorSurface.margin
        var right = surface.width - DecorSurface.margin
        for (i, lamp) in lamps.enumerated() {
            // Two lamps: one at each end.
            if i % 2 == 0 {
                result[lamp.id] = left + lamp.width / 2
                left += lamp.width + DecorSurface.gap
            } else {
                result[lamp.id] = right - lamp.width / 2
                right -= lamp.width + DecorSurface.gap
            }
        }
        // Monitors centered in what's left, side by side.
        let middleWidth = middle.reduce(0) { $0 + $1.width } + DecorSurface.gap * Double(max(middle.count - 1, 0))
        var x = (left + right) / 2 - middleWidth / 2
        if !middle.isEmpty {
            // Leave room on the right for the others.
            let restWidth = rest.reduce(0) { $0 + $1.width + DecorSurface.gap }
            x = min(x, right - restWidth - middleWidth)
            x = max(x, left)
            for m in middle {
                result[m.id] = x + m.width / 2
                x += m.width + DecorSurface.gap
            }
        }
        for piece in rest {
            result[piece.id] = right - piece.width / 2
            right -= piece.width + DecorSurface.gap
        }
        return result
    }

    static func spots(_ assigned: [UUID: [DecorPiece]], surfaces: [DecorSurface], floor: [DecorPiece]) -> [SurfaceSpot] {
        var result: [SurfaceSpot] = []
        for surface in surfaces {
            guard let pieces = assigned[surface.id], !pieces.isEmpty else { continue }
            let offsets = arrange(pieces, on: surface)
            for piece in pieces {
                result.append(SurfaceSpot(itemID: piece.id, hostID: surface.id, offsetCm: offsets[piece.id] ?? surface.width / 2))
            }
        }
        result += floor.map { SurfaceSpot(itemID: $0.id, hostID: nil, offsetCm: 0) }
        return result
    }

    /// Each surface's pieces side by side in its middle, as one group.
    static func centered(_ base: SmallDecorSuggestion, pieces: [DecorPiece], surfaces: [DecorSurface]) -> SmallDecorSuggestion {
        let byID = Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0) })
        var spots = base.spots
        for surface in surfaces {
            let onIt = spots.indices.filter { spots[$0].hostID == surface.id }.sorted { spots[$0].offsetCm < spots[$1].offsetCm }
            let widths = onIt.map { byID[spots[$0].itemID]?.width ?? 0 }
            let total = widths.reduce(0, +) + DecorSurface.gap * Double(max(onIt.count - 1, 0))
            var x = (surface.width - total) / 2
            for (i, index) in onIt.enumerated() {
                spots[index].offsetCm = x + widths[i] / 2
                x += widths[i] + DecorSurface.gap
            }
        }
        return SmallDecorSuggestion(label: "Grouped in the middle",
                                    detail: "The first idea with each surface's pieces gathered together in its middle.",
                                    spots: spots, leftOut: base.leftOut)
    }

    /// True when every piece is on the same surface in about the same spot.
    static func same(_ a: [SurfaceSpot], _ b: [SurfaceSpot]) -> Bool {
        guard a.count == b.count else { return false }
        let other = Dictionary(b.map { ($0.itemID, $0) }, uniquingKeysWith: { x, _ in x })
        return a.allSatisfy { p in
            other[p.itemID].map { $0.hostID == p.hostID && abs($0.offsetCm - p.offsetCm) < 2 } ?? false
        }
    }
}

/// A tiny repeatable random number maker (SplitMix64), so the same room
/// always gets the same ideas.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
