import Foundation

enum IntentType: String, Codable {
    case add
    case delete
    case modify
}

enum ScheduleTarget: String, Codable, CaseIterable {
    case event = "Event"
    case reminder = "Reminder"
}

struct ScheduleIntent: Identifiable, Equatable {
    let id: UUID
    var type: IntentType
    var target: ScheduleTarget
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var notes: String?
    var isAllDay: Bool

    init(
        id: UUID = UUID(), type: IntentType = .add, target: ScheduleTarget = .event, title: String,
        startDate: Date, endDate: Date,
        location: String? = nil, notes: String? = nil, isAllDay: Bool = false
    ) {
        self.id = id
        self.type = type
        self.target = target
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
    }
}
