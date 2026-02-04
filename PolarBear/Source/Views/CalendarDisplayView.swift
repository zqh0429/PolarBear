import EventKit
import SwiftUI

struct CalendarDisplayView: View {
    @ObservedObject var calendarManager: CalendarManager
    @State private var viewMode: CalendarViewMode = .list
    @State private var selectedDate: Date? = Date()
    @State private var showListFilter: Bool = false
    @State private var listFilterDate: Date = Date()

    enum CalendarViewMode: String, CaseIterable {
        case list = "List"
        case month = "Month"
    }

    var body: some View {
        NavigationView {
            VStack {
                if calendarManager.isAuthorized {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 10)  // Add spacing below the picker
                }

                Group {
                    if !calendarManager.isAuthorized {
                        VStack {
                            Text("Access Required")
                                .font(.headline)
                            Text("Please allow access in Settings to view your schedule.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding()
                            Button("Check Permission") {
                                calendarManager.checkPermission()
                            }
                        }
                    } else if calendarManager.events.isEmpty && calendarManager.reminders.isEmpty {
                        VStack {
                            if viewMode == .month {
                                MonthCalendarView(
                                    calendarManager: calendarManager, selectedDate: $selectedDate
                                )
                                .padding()
                                Spacer()
                            }
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.largeTitle)
                                .padding()
                            Text("No upcoming events or tasks")
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    } else {
                        if viewMode == .list {
                            HStack {
                                Toggle("Filter by Date", isOn: $showListFilter)
                                    .labelsHidden()
                                Text("Filter Date")
                                Spacer()
                                if showListFilter {
                                    DatePicker(
                                        "", selection: $listFilterDate, displayedComponents: .date
                                    )
                                    .labelsHidden()
                                }
                            }
                            .padding(.horizontal)

                            // Merge Events and Reminders
                            let combinedItems = self.combinedItems(
                                for: showListFilter ? listFilterDate : nil)

                            if showListFilter && combinedItems.isEmpty {
                                Spacer()
                                Text("No events on \(listFilterDate, style: .date)")
                                    .foregroundColor(.gray)
                                Spacer()
                            } else {
                                EventsListView(
                                    items: combinedItems, calendarManager: calendarManager)
                            }
                        } else {
                            VStack {
                                MonthCalendarView(
                                    calendarManager: calendarManager, selectedDate: $selectedDate
                                )
                                .padding(.top, 60)  // Increased padding to prevent overlap with picker
                                .padding(.bottom, 30)  // Increased spacing
                                .frame(height: 400)  // Constrain height

                                Divider()

                                if let date = selectedDate {
                                    Text("Schedule for \(date, style: .date)")
                                        .font(.headline)
                                        .padding(.top, 8)

                                    let dailyItems = self.combinedItems(for: date)

                                    if dailyItems.isEmpty {
                                        Text("No events for this day")
                                            .foregroundColor(.gray)
                                            .padding()
                                        Spacer()
                                    } else {
                                        EventsListView(
                                            items: dailyItems, calendarManager: calendarManager)
                                    }
                                } else {
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .onAppear {
                calendarManager.fetchEvents()
                calendarManager.fetchReminders()
            }
        }
    }

    // Helper to combine and sort
    func combinedItems(for date: Date?) -> [CalendarItemWrapper] {
        var items: [CalendarItemWrapper] = []

        // Add events
        let relevantEvents = calendarManager.events.filter { event in
            guard let date = date else { return true }
            return Calendar.current.isDate(event.startDate, inSameDayAs: date)
        }
        items.append(contentsOf: relevantEvents.map { .event($0) })

        // Add reminders
        let relevantReminders = calendarManager.reminders.filter { reminder in
            guard let date = date else { return true }
            // For tasks with no due date, maybe show them on "Today" or always if no filter?
            // For now, if filtered by date, only show if due date matches.
            if let dueComponents = reminder.dueDateComponents, let dueDate = dueComponents.date {
                return Calendar.current.isDate(dueDate, inSameDayAs: date)
            }
            // If no due date, and we are filtering, maybe DON'T show? Or show on today?
            // Let's hide if filtering by specific date and no due date.
            return false
        }
        // If NOT filtering (Show All), we should include reminders with/without due dates.
        // But for "Show All", typically we want upcoming.
        // Let's include all reminders if date is nil.
        if date == nil {
            items.append(contentsOf: calendarManager.reminders.map { .reminder($0) })
        } else {
            items.append(contentsOf: relevantReminders.map { .reminder($0) })
        }

        // Sort: Events by start date, Reminders by due date or creation?
        // Let's sort all by "relevant time"
        items.sort { lhs, rhs in
            return lhs.sortDate < rhs.sortDate
        }

        return items
    }
}

enum CalendarItemWrapper: Identifiable {
    case event(EKEvent)
    case reminder(EKReminder)

    var id: String {
        switch self {
        case .event(let e): return e.eventIdentifier
        case .reminder(let r): return r.calendarItemIdentifier
        }
    }

    var sortDate: Date {
        switch self {
        case .event(let e): return e.startDate
        case .reminder(let r): return r.dueDateComponents?.date ?? Date.distantPast
        }
    }
}

struct EventsListView: View {
    let items: [CalendarItemWrapper]
    @ObservedObject var calendarManager: CalendarManager

    var body: some View {
        List {
            ForEach(items) { item in
                switch item {
                case .event(let event):
                    EventRow(event: event, calendarManager: calendarManager)
                case .reminder(let reminder):
                    ReminderRow(reminder: reminder, calendarManager: calendarManager)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let item = items[index]
                    switch item {
                    case .event(let event):
                        calendarManager.deleteEvent(withId: event.eventIdentifier)
                    case .reminder(let reminder):
                        calendarManager.deleteReminder(withId: reminder.calendarItemIdentifier)
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: EKEvent
    @ObservedObject var calendarManager: CalendarManager

    var body: some View {
        HStack {
            Button(action: {
                calendarManager.toggleCompletion(for: event)
            }) {
                Image(
                    systemName: calendarManager.isCompleted(event)
                        ? "checkmark.circle.fill" : "circle"
                )
                .font(.title2)
                .foregroundColor(Color(event.calendar.cgColor))
            }
            .buttonStyle(PlainButtonStyle())

            NavigationLink(
                destination: EventDetailView(
                    event: event, calendarManager: calendarManager)
            ) {
                VStack(alignment: .leading) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundColor(
                            calendarManager.isCompleted(event) ? .gray : .primary
                        )
                        .strikethrough(calendarManager.isCompleted(event))

                    HStack {
                        if event.isAllDay {
                            Text("All Day")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(event.startDate, style: .time)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ReminderRow: View {
    let reminder: EKReminder
    @ObservedObject var calendarManager: CalendarManager

    var body: some View {
        HStack {
            Button(action: {
                calendarManager.toggleCompletion(for: reminder)
            }) {
                Image(
                    systemName: reminder.isCompleted
                        ? "checkmark.circle.fill" : "circle"
                )
                .font(.title2)
                .foregroundColor(Color(reminder.calendar.cgColor))
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundColor(reminder.isCompleted ? .gray : .primary)
                    .strikethrough(reminder.isCompleted)

                if let dueComponents = reminder.dueDateComponents, let date = dueComponents.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
