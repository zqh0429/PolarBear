import EventKit
import SwiftUI

struct JournalListView: View {
    @ObservedObject var journalManager: JournalManager
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var settingsManager: LLMSettingsManager
    @State private var showingAddSheet = false

    var body: some View {
        NavigationView {
            List {
                ForEach(journalManager.entries) { entry in
                    NavigationLink(
                        destination: JournalEntryView(
                            entry: entry, journalManager: journalManager,
                            calendarManager: calendarManager, settingsManager: settingsManager)
                    ) {
                        VStack(alignment: .leading) {
                            Text(entry.date, style: .date)
                                .font(.headline)
                            if !entry.autoSummary.isEmpty {
                                Text(entry.autoSummary)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundColor(.secondary)
                            } else if !entry.content.isEmpty {
                                Text(entry.content)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Empty Entry")
                                    .font(.caption)
                                    .italic()
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: journalManager.delete)
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationView {
                    JournalEntryView(
                        entry: JournalEntry(), journalManager: journalManager,
                        calendarManager: calendarManager, settingsManager: settingsManager,
                        isNew: true)
                }
            }
        }
    }
}

struct JournalEntryView: View {
    @State var entry: JournalEntry
    @ObservedObject var journalManager: JournalManager
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var settingsManager: LLMSettingsManager

    var isNew: Bool = false
    @State private var isGeneratingSummary = false
    @Environment(\.presentationMode) var presentationMode

    // Quick formatter
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }

    var body: some View {
        Form {
            Section(header: Text("Date")) {
                DatePicker("Date", selection: $entry.date, displayedComponents: .date)
                    .onChange(of: entry.date) { _ in
                        // If changing date regarding a new entry, maybe re-generate summary?
                        // For now keep manual regen
                    }
            }

            Section(header: Text("Daily Summary")) {
                if isGeneratingSummary {
                    HStack {
                        ProgressView()
                        Text("Summarizing schedule...")
                    }
                } else {
                    if entry.autoSummary.isEmpty {
                        Button("Generate Summary from Calendar") {
                            generateSummary()
                        }
                    } else {
                        TextEditor(text: $entry.autoSummary)
                            .frame(minHeight: 100)
                        Button("Regenerate Summary") {
                            generateSummary()
                        }
                        .font(.caption)
                    }
                }
            }

            Section(header: Text("My Thoughts")) {
                TextEditor(text: $entry.content)
                    .frame(minHeight: 200)
            }
        }
        .navigationTitle(dateFormatter.string(from: entry.date))
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        journalManager.add(entry: entry)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        journalManager.update(entry: entry)
                        // presentationMode.wrappedValue.dismiss() // Stay on page or dismiss? Usually save implies stay or explicit back.
                        // For standard NavView editing, back button saves automatically if binding used, but here we use manual save for explicit clear update.
                        // Actually, users expect auto-save or 'Done'.
                    }
                }
            }
        }
        .onDisappear {
            if !isNew {
                journalManager.update(entry: entry)
            }
        }
        .onAppear {
            if isNew && entry.autoSummary.isEmpty {
                generateSummary()
            }
        }
    }

    private func generateSummary() {
        isGeneratingSummary = true

        let duration = settingsManager.journalSummaryDuration
        let startDate = Calendar.current.startOfDay(for: entry.date)

        var calendarIDs: Set<String>? = nil
        if !settingsManager.journalSummaryCalendarIDs.isEmpty {
            calendarIDs = settingsManager.journalSummaryCalendarIDs
        }

        var reminderCalendarIDs: Set<String>? = nil
        if !settingsManager.journalSummaryReminderCalendarIDs.isEmpty {
            reminderCalendarIDs = settingsManager.journalSummaryReminderCalendarIDs
        }

        let events = calendarManager.fetchEvents(
            for: duration, startingFrom: startDate, calendarIDs: calendarIDs)

        // Asynchronous fetching
        Task {
            let reminders = await calendarManager.fetchReminders(
                for: duration, startingFrom: startDate, calendarIDs: reminderCalendarIDs)

            if events.isEmpty && reminders.isEmpty {
                DispatchQueue.main.async {
                    self.entry.autoSummary =
                        "No events or reminders found for the selected duration."
                    self.isGeneratingSummary = false
                }
                return
            }

            // Construct text with date if multi-day
            var scheduleText = events.map { event in
                let dateStr = DateFormatter.localizedString(
                    from: event.startDate, dateStyle: .short, timeStyle: .none)
                let time = DateFormatter.localizedString(
                    from: event.startDate, dateStyle: .none, timeStyle: .short)
                return
                    "- [Event] [\(dateStr)] \(time): \(event.title ?? "No Title") (\(event.isAllDay ? "All Day" : "Duration: " + String(format: "%.1f h", event.endDate.timeIntervalSince(event.startDate)/3600)))"
            }.joined(separator: "\n")

            if !reminders.isEmpty {
                let reminderText = reminders.map { reminder in
                    let dateStr: String
                    if let components = reminder.dueDateComponents,
                        let date = Calendar.current.date(from: components)
                    {
                        dateStr = DateFormatter.localizedString(
                            from: date, dateStyle: .short, timeStyle: .short)
                    } else {
                        dateStr = "No Due Date"
                    }
                    return "- [Reminder] [\(dateStr)]: \(reminder.title ?? "Reminder")"
                }.joined(separator: "\n")

                if !scheduleText.isEmpty {
                    scheduleText += "\n"
                }
                scheduleText += reminderText
            }

            // Proceed to LLM
            await self.callLLM(scheduleText: scheduleText)
        }
    }

    // Extracted LLM call to a separate method to keep clean, or just inline it since we are in Task
    func callLLM(scheduleText: String) async {
        let llmService: LLMServiceProtocol
        if settingsManager.mode == .custom, let url = URL(string: settingsManager.customURL),
            !settingsManager.customAPIKey.isEmpty
        {
            llmService = OpenAILLMService(url: url, apiKey: settingsManager.customAPIKey)
        } else {
            llmService = OpenAILLMService(
                url: URL(
                    string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
                apiKey: "sk-d77631691a6541b4aa7bb6ccf0d2d866")
        }

        do {
            let summary = try await llmService.summarize(scheduleText: scheduleText)
            DispatchQueue.main.async {
                self.entry.autoSummary = summary
                self.isGeneratingSummary = false
            }
        } catch {
            DispatchQueue.main.async {
                self.entry.autoSummary =
                    "Failed to generate summary: \(error.localizedDescription)"
                self.isGeneratingSummary = false
            }
        }
    }

    /*
    // Old sync logic replaced
    /*
        if events.isEmpty { ... }
    
        let scheduleText = ...
    
        Task {
            ...
        }
    */
    */
}
