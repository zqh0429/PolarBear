import Combine
import Foundation

class FocusHistoryManager: ObservableObject {
    static let shared = FocusHistoryManager()

    @Published var history: [FocusSession] = []

    private let historyKey = "FocusHistory"

    private init() {
        loadHistory()
    }

    func saveSession(duration: Int, taskName: String?, planId: UUID? = nil, planName: String? = nil)
    {
        let session = FocusSession(
            date: Date(), durationBytes: duration, taskName: taskName, planId: planId,
            planName: planName)
        history.append(session)
        saveHistory()
    }

    func deleteSession(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func deletePlan(planId: UUID) {
        history.removeAll { $0.planId == planId }
        saveHistory()
    }

    func renameSession(id: UUID, newName: String) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].taskName = newName
            saveHistory()
        }
    }

    func renamePlan(planId: UUID, newName: String) {
        for index in history.indices {
            if history[index].planId == planId {
                history[index].planName = newName
            }
        }
        saveHistory()
    }

    func getLast7DaysDailyFocus() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        var dailyFocus: [Date: Int] = [:]

        // Initialize last 7 days with 0
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let startOfDay = calendar.startOfDay(for: date)
                dailyFocus[startOfDay] = 0
            }
        }

        for session in history {
            let startOfDay = calendar.startOfDay(for: session.date)
            // Only count if within the last 7 days window we initialized
            if dailyFocus[startOfDay] != nil {
                dailyFocus[startOfDay, default: 0] += session.durationBytes / 60
            }
        }

        return dailyFocus.sorted { $0.key < $1.key }.map { (date: $0.key, minutes: $0.value) }
    }

    func getTaskDistribution(startDate: Date? = nil, endDate: Date? = nil) -> [(
        name: String, minutes: Int
    )] {
        var distribution: [String: Int] = [:]
        let calendar = Calendar.current

        let filteredHistory = history.filter { session in
            if let start = startDate, let end = endDate {
                let startOfDay = calendar.startOfDay(for: start)
                let endOfDay =
                    calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
                return session.date >= startOfDay && session.date <= endOfDay
            }
            return true
        }

        for session in filteredHistory {
            let name = session.taskName ?? "Untitled"
            distribution[name, default: 0] += session.durationBytes / 60
        }

        return distribution.sorted { $0.value > $1.value }.map { (name: $0.key, minutes: $0.value) }
    }

    func getFlexibleDistribution(
        startDate: Date? = nil, endDate: Date? = nil, groupPlans: Bool = true
    ) -> [ChartItem] {
        let calendar = Calendar.current
        var items: [ChartItem] = []

        // 1. Filter history by date
        let filteredHistory = history.filter { session in
            if let start = startDate, let end = endDate {
                let startOfDay = calendar.startOfDay(for: start)
                let endOfDay =
                    calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
                return session.date >= startOfDay && session.date <= endOfDay
            }
            return true
        }

        // 2. Group by Plan vs Standalone Task
        var planGroups: [UUID: [FocusSession]] = [:]
        var standaloneSessions: [FocusSession] = []
        var planNames: [UUID: String] = [:]

        for session in filteredHistory {
            if let pid = session.planId {
                planGroups[pid, default: []].append(session)
                if let pName = session.planName {
                    planNames[pid] = pName
                }
            } else {
                standaloneSessions.append(session)
            }
        }

        // 3. Create ChartItems

        // A. Standalone Tasks
        // Aggregate by task name for cleaner viewing
        var standaloneDistribution: [String: Int] = [:]
        for session in standaloneSessions {
            let name = session.taskName ?? "Untitled"
            standaloneDistribution[name, default: 0] += session.durationBytes / 60
        }
        for (name, minutes) in standaloneDistribution {
            // Create a stable ID based on name for animation stability
            let stableId =
                UUID(
                    uuidString: "00000000-0000-0000-0000-"
                        + String(format: "%012X", name.hashValue).suffix(12)) ?? UUID()
            items.append(
                ChartItem(
                    id: stableId, name: name, minutes: minutes, isPlan: false, planId: nil,
                    parentPlanId: nil))
        }

        // B. Plans
        for (pid, sessions) in planGroups {
            let pName = planNames[pid] ?? "Focus Plan"

            if !groupPlans {
                // If ungrouped, show individual tasks for ALL plans
                var taskDistribution: [String: Int] = [:]
                for session in sessions {
                    let tName = session.taskName ?? "Untitled"
                    taskDistribution[tName, default: 0] += session.durationBytes / 60
                }
                for (tName, minutes) in taskDistribution {
                    // Mark as NOT a plan itself, but linked to parentPlanId
                    // Stable ID: Mix of planID and task name hash
                    let combinedHash = pid.hashValue ^ tName.hashValue
                    let stableId =
                        UUID(
                            uuidString: "00000000-0000-0000-0000-"
                                + String(format: "%012X", combinedHash).suffix(12)) ?? UUID()
                    items.append(
                        ChartItem(
                            id: stableId, name: tName, minutes: minutes, isPlan: false, planId: nil,
                            parentPlanId: pid))
                }
            } else {
                // Grouped: Show as one block. Use planId as the ID.
                let totalMinutes = sessions.reduce(0) { $0 + $1.durationBytes } / 60
                items.append(
                    ChartItem(
                        id: pid, name: pName, minutes: totalMinutes, isPlan: true, planId: pid,
                        parentPlanId: nil))
            }
        }

        return items.filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
            let decoded = try? JSONDecoder().decode([FocusSession].self, from: data)
        {
            history = decoded
        }
    }

    func getDailyTotal(for date: Date = Date()) -> Int {
        let calendar = Calendar.current
        return history.filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.durationBytes }
    }
}
