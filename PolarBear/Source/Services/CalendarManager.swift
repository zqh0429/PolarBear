import Combine
import EventKit
import Foundation

class CalendarManager: ObservableObject {
    private let eventStore = EKEventStore()
    @Published var isAuthorized = false
    @Published var canReadEvents = false
    @Published var error: Error?
    @Published var events: [EKEvent] = []
    @Published var reminders: [EKReminder] = []

    @Published var availableCalendars: [EKCalendar] = []
    @Published var availableReminderCalendars: [EKCalendar] = []  // For Reminders

    @Published var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
            fetchEvents()
        }
    }

    @Published var selectedReminderCalendarIDs: Set<String> = [] {  // For Reminders
        didSet {
            UserDefaults.standard.set(
                Array(selectedReminderCalendarIDs), forKey: "selectedReminderCalendarIDs")
            fetchReminders()
        }
    }

    @Published var defaultCalendarID: String? {
        didSet {
            UserDefaults.standard.set(defaultCalendarID, forKey: "defaultCalendarID")
        }
    }

    @Published var defaultReminderCalendarID: String? {  // Default list for new reminders
        didSet {
            UserDefaults.standard.set(
                defaultReminderCalendarID, forKey: "defaultReminderCalendarID")
        }
    }

    init() {
        // Load persisted settings
        if let savedIDs = UserDefaults.standard.array(forKey: "selectedCalendarIDs") as? [String] {
            selectedCalendarIDs = Set(savedIDs)
        }
        if let savedReminderIDs = UserDefaults.standard.array(forKey: "selectedReminderCalendarIDs")
            as? [String]
        {
            selectedReminderCalendarIDs = Set(savedReminderIDs)
        }

        defaultCalendarID = UserDefaults.standard.string(forKey: "defaultCalendarID")
        defaultReminderCalendarID = UserDefaults.standard.string(
            forKey: "defaultReminderCalendarID")

        // Load completed events
        if let completedIDs = UserDefaults.standard.array(forKey: "completedEventIDs") as? [String]
        {
            completedEventIDs = Set(completedIDs)
        }

        checkPermission()
    }

    // ...

    // (Inside fetchCalendars - Reminder section)
    //    func fetchCalendars() {
    //      ...
    //      if reminderStatus == .authorized || reminderStatus == .fullAccess {
    //             let reminderCalendars = eventStore.calendars(for: .reminder)
    //             DispatchQueue.main.async {
    //                 self.availableReminderCalendars = reminderCalendars
    //
    //                 // Default to all selected if empty
    //                 if self.selectedReminderCalendarIDs.isEmpty {
    //                     self.selectedReminderCalendarIDs = Set(reminderCalendars.map { $0.calendarIdentifier })
    //                 }
    //
    //                 // Set default reminder ID if not set
    //                 if self.defaultReminderCalendarID == nil || !reminderCalendars.contains(where: { $0.calendarIdentifier == self.defaultReminderCalendarID }) {
    //                     self.defaultReminderCalendarID = self.eventStore.defaultCalendarForNewReminders()?.calendarIdentifier ?? reminderCalendars.first?.calendarIdentifier
    //                 }
    //             }
    //        }
    //    }

    // Since I can't easily edit fetchCalendars mid-function with replace_file_content given the chunk size limits or context, I will update fetchCalendars entirely or just adding the property first.
    // Actually, I will update the init and property declarations first as requested in the replacement.

    // Wait, I need to be careful with the ReplaceContent application. I'll just replace the property definitions and init.

    // And for addReminder:

    func addReminder(from intent: ScheduleIntent, to targetCalendar: EKCalendar? = nil) throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = intent.title
        reminder.notes = intent.notes

        // Set due date from start date
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: intent.startDate)
        reminder.dueDateComponents = components

        // Determine calendar to use
        var calendarToUse: EKCalendar? = targetCalendar

        if calendarToUse == nil {
            if let defaultID = defaultReminderCalendarID,
                let found = availableReminderCalendars.first(where: {
                    $0.calendarIdentifier == defaultID
                })
            {
                calendarToUse = found
            } else {
                calendarToUse = eventStore.defaultCalendarForNewReminders()
            }
        }

        if let cal = calendarToUse {
            reminder.calendar = cal
        } else {
            // Fallback if absolutely nothing found (unlikely if authorized)
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        try eventStore.save(reminder, commit: true)
        fetchReminders()
    }

    @Published var completedEventIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(completedEventIDs), forKey: "completedEventIDs")
        }
    }

    func toggleCompletion(for event: EKEvent) {
        if completedEventIDs.contains(event.eventIdentifier) {
            completedEventIDs.remove(event.eventIdentifier)
        } else {
            completedEventIDs.insert(event.eventIdentifier)
        }
    }

    func toggleCompletion(for reminder: EKReminder) {
        reminder.isCompleted.toggle()
        do {
            try eventStore.save(reminder, commit: true)
            fetchReminders()  // Refresh list
        } catch {
            print("Failed to save reminder state: \(error.localizedDescription)")
            self.error = error
        }
    }

    func isCompleted(_ event: EKEvent) -> Bool {
        return completedEventIDs.contains(event.eventIdentifier)
    }

    func checkPermission() {
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)

        print(
            "CalendarManager: Event status: \(eventStatus.rawValue), Reminder status: \(reminderStatus.rawValue)"
        )

        // We consider "authorized" if at least Calendar is authorized for now, or both.
        // Ideally we want both.

        var calendarAccess = false
        var reminderAccess = false

        switch eventStatus {
        case .authorized, .fullAccess:
            calendarAccess = true
        case .writeOnly:
            // Write only is "access" but limited. We treat it as true-ish but with flags.
            calendarAccess = true
        default:
            calendarAccess = false
        }

        switch reminderStatus {
        case .authorized, .fullAccess:
            reminderAccess = true
        default:
            reminderAccess = false
        }

        if calendarAccess {
            isAuthorized = true
            canReadEvents = (eventStatus == .authorized || eventStatus == .fullAccess)
            fetchCalendars()
            fetchEvents()
        }

        if reminderAccess {
            // fetchCalendars will also handle reminder calendars now
            if !calendarAccess {  // Only call if not already called by event access
                fetchCalendars()
            }
            fetchReminders()
        }

        // If neither, try to request.
        if !calendarAccess && eventStatus == .notDetermined {
            requestPermission()
        }
        if !reminderAccess && reminderStatus == .notDetermined {
            requestRemindersPermission()
        }
    }

    func requestPermission() {
        if #available(iOS 17.0, *) {
            print("CalendarManager: Requesting full access (iOS 17+)...")
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    print(
                        "CalendarManager: Request completed. Granted: \(granted), Error: \(String(describing: error))"
                    )
                    self?.error = error
                    // Re-check status to set correct flags
                    self?.checkPermission()
                }
            }
        } else {
            print("CalendarManager: Requesting access (iOS <17)...")
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    print(
                        "CalendarManager: Request completed. Granted: \(granted), Error: \(String(describing: error))"
                    )
                    self?.error = error
                    // Re-check status to set correct flags
                    self?.checkPermission()
                }
            }
        }
    }

    func requestRemindersPermission() {
        print("CalendarManager: Requesting reminders access...")
        eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
            DispatchQueue.main.async {
                print("CalendarManager: Reminders request completed. Granted: \(granted)")
                if let error = error {
                    self?.error = error
                }
                self?.checkPermission()
            }
        }
    }

    func fetchCalendars() {
        // Fetch Event Calendars
        if canReadEvents {
            let calendars = eventStore.calendars(for: .event)
            DispatchQueue.main.async {
                self.availableCalendars = calendars

                // If no calendars are selected (first run), select all by default
                if self.selectedCalendarIDs.isEmpty {
                    self.selectedCalendarIDs = Set(calendars.map { $0.calendarIdentifier })
                }

                // If default calendar is invalid or not set, try to set a reasonable default
                if self.defaultCalendarID == nil
                    || !calendars.contains(where: {
                        $0.calendarIdentifier == self.defaultCalendarID
                    })
                {
                    self.defaultCalendarID =
                        self.eventStore.defaultCalendarForNewEvents?.calendarIdentifier
                        ?? calendars.first?.calendarIdentifier
                }
            }
        }

        // Fetch Reminder Calendars
        // Note: We might be authorized for Reminders but not Events, or vice versa
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        if reminderStatus == .authorized || reminderStatus == .fullAccess {
            let reminderCalendars = eventStore.calendars(for: .reminder)
            DispatchQueue.main.async {
                self.availableReminderCalendars = reminderCalendars

                // Default to all selected if empty
                if self.selectedReminderCalendarIDs.isEmpty {
                    self.selectedReminderCalendarIDs = Set(
                        reminderCalendars.map { $0.calendarIdentifier })
                }
            }
        }
    }

    func toggleCalendar(id: String) {
        if selectedCalendarIDs.contains(id) {
            selectedCalendarIDs.remove(id)
        } else {
            selectedCalendarIDs.insert(id)
        }
    }

    func toggleReminderCalendar(id: String) {
        if selectedReminderCalendarIDs.contains(id) {
            selectedReminderCalendarIDs.remove(id)
        } else {
            selectedReminderCalendarIDs.insert(id)
        }
    }

    func fetchEvents() {
        // Fetch events for a wider range (1 year back, 1 year forward)
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now

        // Filter calendars based on selection
        let calendarsToFetch = availableCalendars.filter {
            selectedCalendarIDs.contains($0.calendarIdentifier)
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate, end: endDate,
            calendars: calendarsToFetch.isEmpty ? nil : calendarsToFetch)
        let fetchedEvents = eventStore.events(matching: predicate)

        DispatchQueue.main.async {
            self.events = fetchedEvents.sorted { $0.startDate < $1.startDate }
        }
    }

    func fetchReminders() {
        // Filter by selectedReminderCalendarIDs
        // If empty (e.g. before fetch), we might pass nil (which means ALL), but we want to respect selection if it exists.
        // However, `predicateForReminders` takes [EKCalendar]?
        // If we want to restrict, we find the EKCalendars matching our IDs.

        var calendarsToFetch: [EKCalendar]? = nil
        if !selectedReminderCalendarIDs.isEmpty {
            calendarsToFetch = availableReminderCalendars.filter {
                selectedReminderCalendarIDs.contains($0.calendarIdentifier)
            }
        } else if !availableReminderCalendars.isEmpty {
            // If we have available calendars but none selected, it implies "None"
            calendarsToFetch = []
        }

        // If calendarsToFetch is [] (empty list), predicateForReminders(in: []) returns reminders in those lists (none).
        // If calendarsToFetch is nil, it searches all.
        // We want: if initialized and none selected -> none. If first run (all selected) -> all.
        // Our logic above: if selectedReminderCalendarIDs is empty, maybe we should return empty?
        // But in `fetchCalendars`, we default `selectedReminderCalendarIDs` to ALL.
        // So if it's empty here, it really means user deselected all.

        let predicate = eventStore.predicateForReminders(in: calendarsToFetch)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            DispatchQueue.main.async {
                self?.reminders =
                    reminders?.sorted {
                        // Sort by due date, then creation date.
                        // Note: dueDateComponents needs to be converted to Date for comparison
                        let date1 = $0.dueDateComponents?.date ?? Date.distantFuture
                        let date2 = $1.dueDateComponents?.date ?? Date.distantFuture
                        return date1 < date2
                    } ?? []
            }
        }
    }

    func fetchEvents(
        for duration: SummaryDuration, startingFrom startDate: Date = Date(),
        calendarIDs: Set<String>? = nil
    ) -> [EKEvent] {
        // This is for summary generation - focusing on Events for now as per original request,
        // but could extend to Reminders later.
        guard isAuthorized else { return [] }

        let endDate =
            Calendar.current.date(byAdding: .day, value: duration.days, to: startDate) ?? startDate

        var calendars: [EKCalendar]? = nil
        if let ids = calendarIDs, !ids.isEmpty {
            calendars = availableCalendars.filter { ids.contains($0.calendarIdentifier) }
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate, end: endDate, calendars: calendars)

        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func fetchReminders(
        for duration: SummaryDuration, startingFrom startDate: Date = Date(),
        calendarIDs: Set<String>? = nil
    ) async -> [EKReminder] {
        guard isAuthorized else { return [] }

        let endDate =
            Calendar.current.date(byAdding: .day, value: duration.days, to: startDate) ?? startDate

        var calendars: [EKCalendar]? = nil
        if let ids = calendarIDs, !ids.isEmpty {
            calendars = availableReminderCalendars.filter { ids.contains($0.calendarIdentifier) }
        }

        // Reminder predicate usually just takes calendars, but we want to filter by due date.
        // fetchReminders(matching:) returns all reminders (completed or not) matching the predicate.
        // predicateForReminders(in:) fetches all incomplete.
        // predicateForIncompleteReminders(withDueDateStarting:ending:calendars:) available?
        // No, standard predicateForReminders(in:) + manual filtering or predicateForReminders(in: ...)?
        // Actually, efficiently creating a predicate for date range on Reminders is tricky with older APIs.
        // The standard `predicateForReminders(in:)` fetches all incomplete reminders.
        // Completed reminders predicate: `predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)`

        // For "Upcoming Schedule", we probably want incomplete reminders due within the range.

        let predicate = eventStore.predicateForReminders(in: calendars)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let filtered =
                    reminders?.filter { reminder in
                        guard !reminder.isCompleted else { return false }
                        guard let dueDateComponents = reminder.dueDateComponents,
                            let dueDate = Calendar.current.date(from: dueDateComponents)
                        else {
                            return false  // No due date = logic decision. Maybe include or exclude? Exclude from "schedule" usually.
                        }
                        return dueDate >= startDate && dueDate <= endDate
                    } ?? []

                continuation.resume(
                    returning: filtered.sorted {
                        let d1 = $0.dueDateComponents?.date ?? Date.distantFuture
                        let d2 = $1.dueDateComponents?.date ?? Date.distantFuture
                        return d1 < d2
                    })
            }
        }
    }

    func saveEvent(_ event: EKEvent) throws {
        try eventStore.save(event, span: .thisEvent)
        fetchEvents()
    }

    func addEvent(from intent: ScheduleIntent, to targetCalendar: EKCalendar? = nil) throws {
        // Re-check status for better error messaging
        let status = EKEventStore.authorizationStatus(for: .event)

        guard isAuthorized else {
            throw NSError(
                domain: "CalendarManager", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No calendar access"])
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = intent.title
        event.startDate = intent.startDate
        event.endDate = intent.endDate
        event.isAllDay = intent.isAllDay
        event.location = intent.location
        event.notes = intent.notes

        // Use provided calendar, or falling back to user-selected default, or system default
        var calendarToUse: EKCalendar? = targetCalendar

        if calendarToUse == nil {
            if let defaultID = defaultCalendarID,
                let found = availableCalendars.first(where: { $0.calendarIdentifier == defaultID })
            {
                calendarToUse = found
            } else {
                calendarToUse = eventStore.defaultCalendarForNewEvents
            }
        }

        guard let calendar = calendarToUse else {
            throw NSError(
                domain: "CalendarManager", code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No valid calendar found. Please verify your Calendar app."
                ])
        }
        event.calendar = calendar

        try saveEvent(event)
    }

    func addReminder(from intent: ScheduleIntent) throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = intent.title
        reminder.notes = intent.notes

        // Set due date from start date
        let calendar = Calendar.current
        let components: DateComponents
        if intent.isAllDay {
            components = calendar.dateComponents(
                [.year, .month, .day], from: intent.startDate)
        } else {
            components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: intent.startDate)
        }
        reminder.dueDateComponents = components

        // Default to default reminder list
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        try eventStore.save(reminder, commit: true)
        fetchReminders()
    }

    func deleteEvent(from intent: ScheduleIntent) throws -> String {
        // ... (Fuzzy delete logic for EVENTS only for now, as fuzzy matching reminders is trickier with just titles)
        // If the intent explicitly targets reminders, we should handle that, but the current UI flow for delete
        // usually comes from the list view (Swipe to delete) or explicit "Delete X" valid commands.
        // For "Delete X" command, we check intent type.

        if intent.target == .reminder {
            return try deleteReminder(from: intent)
        }

        guard canReadEvents else {
            throw NSError(
                domain: "CalendarManager", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Cannot read events to delete"])
        }

        // Fuzzy match: Look for events with similar title around the start time
        // Search window: +/- 2 hours around intent start time
        let searchStart = intent.startDate.addingTimeInterval(-7200)
        let searchEnd = intent.startDate.addingTimeInterval(7200)
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart, end: searchEnd, calendars: nil)
        let existingEvents = eventStore.events(matching: predicate)

        // Simple fuzzy match: check if title contains the intent title or vice versa
        let candidates = existingEvents.filter { event in
            return event.title.localizedCaseInsensitiveContains(intent.title)
                || intent.title.localizedCaseInsensitiveContains(event.title)
        }

        guard let eventToDelete = candidates.first else {
            throw NSError(
                domain: "CalendarManager", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "No matching event found to delete."])
        }

        try eventStore.remove(eventToDelete, span: .thisEvent)
        fetchEvents()
        return "Deleted event: \(eventToDelete.title)"
    }

    func deleteReminder(from intent: ScheduleIntent) throws -> String {
        // Fuzzy match for reminders is harder because they don't always have a set time range query.
        // We will search ALL Reminders for a title match.
        // This is expensive if there are many reminders, but acceptable for a prototype.

        // We must have already fetched reminders.
        let candidates = reminders.filter { reminder in
            return reminder.title.localizedCaseInsensitiveContains(intent.title)
                || intent.title.localizedCaseInsensitiveContains(reminder.title)
        }

        guard let reminderToDelete = candidates.first else {
            throw NSError(
                domain: "CalendarManager", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "No matching reminder found to delete."])
        }

        try eventStore.remove(reminderToDelete, commit: true)
        fetchReminders()
        return "Deleted reminder: \(reminderToDelete.title ?? "Untitled")"
    }

    func deleteEvent(withId identifier: String) {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent)
            fetchEvents()
        } catch {
            self.error = error
        }
    }

    func deleteReminder(withId identifier: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
        else { return }
        do {
            try eventStore.remove(reminder, commit: true)
            fetchReminders()
        } catch {
            self.error = error
        }
    }

    func modifyEvent(from intent: ScheduleIntent) throws -> String {
        guard canReadEvents else {
            throw NSError(
                domain: "CalendarManager", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Cannot read events to modify"])
        }

        // Fuzzy match search similar to delete
        let searchStart = intent.startDate.addingTimeInterval(-86400)  // Look back 24 hours just in case
        let searchEnd = intent.startDate.addingTimeInterval(86400)  // Look forward 24 hours
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart, end: searchEnd, calendars: nil)
        let existingEvents = eventStore.events(matching: predicate)

        let candidates = existingEvents.filter { event in
            return event.title.localizedCaseInsensitiveContains(intent.title)
                || intent.title.localizedCaseInsensitiveContains(event.title)
        }

        guard let eventToModify = candidates.first else {
            throw NSError(
                domain: "CalendarManager", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "No matching event found to modify."])
        }

        eventToModify.title = intent.title  // Keep title or update if user said "Rename X to Y" (LLM handling of this is basic for now)
        eventToModify.startDate = intent.startDate
        eventToModify.startDate = intent.startDate
        eventToModify.endDate = intent.endDate
        eventToModify.isAllDay = intent.isAllDay

        if let location = intent.location {
            eventToModify.location = location
        }

        if let notes = intent.notes {
            eventToModify.notes = notes
        }

        try eventStore.save(eventToModify, span: .thisEvent)
        fetchEvents()
        return "Modified event: \(eventToModify.title)"
    }
}
