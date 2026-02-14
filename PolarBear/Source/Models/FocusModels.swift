import Foundation

struct FocusSession: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var durationBytes: Int  // Duration in seconds
    var taskName: String?
    var planId: UUID?
    var planName: String?
}

struct FocusTask: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var durationMinutes: Int
    var isCompleted: Bool = false
}

struct ChartItem: Identifiable, Equatable {
    var id: UUID = UUID()
    let name: String
    let minutes: Int
    let isPlan: Bool
    let planId: UUID?
    let parentPlanId: UUID?  // If this is a task inside a plan, this is the plan's ID
}
