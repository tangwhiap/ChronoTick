import Foundation
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String?
    var isBuiltIn: Bool
    var builtInKey: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        isBuiltIn: Bool = false,
        builtInKey: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isBuiltIn = isBuiltIn
        self.builtInKey = builtInKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checkIns = []
    }
}
