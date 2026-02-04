import EventKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: LLMSettingsManager
    @ObservedObject var calendarManager: CalendarManager

    @State private var tempAPIKey: String = ""

    init(settingsManager: LLMSettingsManager, calendarManager: CalendarManager) {
        self.settingsManager = settingsManager
        self.calendarManager = calendarManager
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("LLM Configuration")) {
                    Picker("Mode", selection: $settingsManager.mode) {
                        ForEach(LLMMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if settingsManager.mode == .default {
                        VStack(alignment: .leading) {
                            Text("URL: https://dashscope.aliyuncs.com/compatible-mode/v1")
                            Text("Key: sk-...")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                }

                if settingsManager.mode == .custom {
                    Section(header: Text("Custom Server")) {
                        TextField("Endpoint URL", text: $settingsManager.customURL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)

                        TextField("Model Name (e.g. gpt-4)", text: $settingsManager.customModel)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        SecureField("API Key", text: $settingsManager.customAPIKey)
                    }
                }

                Section(header: Text("Calendar Settings")) {
                    if calendarManager.availableCalendars.isEmpty {
                        Text("No calendars found or access denied.")
                            .foregroundColor(.gray)
                    } else {
                        Picker("Default Calendar", selection: $calendarManager.defaultCalendarID) {
                            Text("System Default").tag(String?.none)
                            ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) {
                                calendar in
                                Text(calendar.title).tag(String?.some(calendar.calendarIdentifier))
                            }
                        }

                        NavigationLink(
                            destination: CalendarSelectionView(calendarManager: calendarManager)
                        ) {
                            Text("Visible Calendars")
                            Spacer()
                            Text("\(calendarManager.selectedCalendarIDs.count) selected")
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section(header: Text("Reminder Settings")) {
                    if calendarManager.availableReminderCalendars.isEmpty {
                        Text("No reminder lists found or access denied.")
                            .foregroundColor(.gray)
                    } else {
                        Picker(
                            "Default List", selection: $calendarManager.defaultReminderCalendarID
                        ) {
                            Text("System Default").tag(String?.none)
                            ForEach(
                                calendarManager.availableReminderCalendars, id: \.calendarIdentifier
                            ) {
                                calendar in
                                Text(calendar.title).tag(String?.some(calendar.calendarIdentifier))
                            }
                        }

                        NavigationLink(
                            destination: ReminderSelectionView(calendarManager: calendarManager)
                        ) {
                            Text("Visible Reminder Lists")
                            Spacer()
                            Text("\(calendarManager.selectedReminderCalendarIDs.count) selected")
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section(header: Text("UI Preferences")) {
                    Toggle("Show Debug Output", isOn: $settingsManager.showDebugOutput)
                }

                Section(header: Text("Schedule Summary Settings")) {
                    Picker("Summary Duration", selection: $settingsManager.summaryDuration) {
                        ForEach(SummaryDuration.allCases) { duration in
                            Text(duration.rawValue).tag(duration)
                        }
                    }

                    NavigationLink(
                        destination: SummaryCalendarSelectionView(
                            calendarManager: calendarManager, settingsManager: settingsManager)
                    ) {
                        Text("Calendars to Summarize")
                        Spacer()
                        Text(
                            "\(settingsManager.summaryCalendarIDs.count + settingsManager.summaryReminderCalendarIDs.count) selected"
                        )
                        .foregroundColor(.gray)
                    }
                }

                Section(header: Text("Journal Summary Settings")) {
                    Picker("Summary Duration", selection: $settingsManager.journalSummaryDuration) {
                        ForEach(SummaryDuration.allCases) { duration in
                            Text(duration.rawValue).tag(duration)
                        }
                    }

                    NavigationLink(
                        destination: JournalSummaryCalendarSelectionView(
                            calendarManager: calendarManager, settingsManager: settingsManager)
                    ) {
                        Text("Calendars to Summarize")
                        Spacer()
                        Text(
                            "\(settingsManager.journalSummaryCalendarIDs.count + settingsManager.journalSummaryReminderCalendarIDs.count) selected"
                        )
                        .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct CalendarSelectionView: View {
    @ObservedObject var calendarManager: CalendarManager

    var body: some View {
        List {
            ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) { calendar in
                HStack {
                    Circle()
                        .fill(Color(calendar.cgColor))
                        .frame(width: 10, height: 10)
                    Text(calendar.title)
                    Spacer()
                    if calendarManager.selectedCalendarIDs.contains(calendar.calendarIdentifier) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    calendarManager.toggleCalendar(id: calendar.calendarIdentifier)
                }
            }
        }
        .navigationTitle("Visible Calendars")
    }
}

struct ReminderSelectionView: View {
    @ObservedObject var calendarManager: CalendarManager

    var body: some View {
        List {
            ForEach(calendarManager.availableReminderCalendars, id: \.calendarIdentifier) {
                calendar in
                HStack {
                    Circle()
                        .fill(Color(calendar.cgColor))
                        .frame(width: 10, height: 10)
                    Text(calendar.title)
                    Spacer()
                    if calendarManager.selectedReminderCalendarIDs.contains(
                        calendar.calendarIdentifier)
                    {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    calendarManager.toggleReminderCalendar(id: calendar.calendarIdentifier)
                }
            }
        }
        .navigationTitle("Visible Lists")
    }
}

struct SummaryCalendarSelectionView: View {
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var settingsManager: LLMSettingsManager

    var body: some View {
        Form {
            Section(header: Text("Event Calendars")) {
                if calendarManager.availableCalendars.isEmpty {
                    Text("No calendars found.")
                } else {
                    ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) {
                        calendar in
                        HStack {
                            Circle()
                                .fill(Color(calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            Spacer()
                            if settingsManager.summaryCalendarIDs.contains(
                                calendar.calendarIdentifier)
                            {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSummaryCalendar(id: calendar.calendarIdentifier)
                        }
                    }
                }
            }

            Section(header: Text("Reminder Lists")) {
                if calendarManager.availableReminderCalendars.isEmpty {
                    Text("No reminder lists found.")
                } else {
                    ForEach(calendarManager.availableReminderCalendars, id: \.calendarIdentifier) {
                        calendar in
                        HStack {
                            Circle()
                                .fill(Color(calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            Spacer()
                            if settingsManager.summaryReminderCalendarIDs.contains(
                                calendar.calendarIdentifier)
                            {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSummaryReminderCalendar(id: calendar.calendarIdentifier)
                        }
                    }
                }
            }
        }
        .navigationTitle("Summary Content")
    }

    private func toggleSummaryCalendar(id: String) {
        if settingsManager.summaryCalendarIDs.contains(id) {
            settingsManager.summaryCalendarIDs.remove(id)
        } else {
            settingsManager.summaryCalendarIDs.insert(id)
        }
    }

    private func toggleSummaryReminderCalendar(id: String) {
        if settingsManager.summaryReminderCalendarIDs.contains(id) {
            settingsManager.summaryReminderCalendarIDs.remove(id)
        } else {
            settingsManager.summaryReminderCalendarIDs.insert(id)
        }
    }
}

struct JournalSummaryCalendarSelectionView: View {
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var settingsManager: LLMSettingsManager

    var body: some View {
        Form {
            Section(header: Text("Event Calendars")) {
                if calendarManager.availableCalendars.isEmpty {
                    Text("No calendars found.")
                } else {
                    ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) {
                        calendar in
                        HStack {
                            Circle()
                                .fill(Color(calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            Spacer()
                            if settingsManager.journalSummaryCalendarIDs.contains(
                                calendar.calendarIdentifier)
                            {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSummaryCalendar(id: calendar.calendarIdentifier)
                        }
                    }
                }
            }

            Section(header: Text("Reminder Lists")) {
                if calendarManager.availableReminderCalendars.isEmpty {
                    Text("No reminder lists found.")
                } else {
                    ForEach(calendarManager.availableReminderCalendars, id: \.calendarIdentifier) {
                        calendar in
                        HStack {
                            Circle()
                                .fill(Color(calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            Spacer()
                            if settingsManager.journalSummaryReminderCalendarIDs.contains(
                                calendar.calendarIdentifier)
                            {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSummaryReminderCalendar(id: calendar.calendarIdentifier)
                        }
                    }
                }
            }
        }
        .navigationTitle("Journal Content")
    }

    private func toggleSummaryCalendar(id: String) {
        if settingsManager.journalSummaryCalendarIDs.contains(id) {
            settingsManager.journalSummaryCalendarIDs.remove(id)
        } else {
            settingsManager.journalSummaryCalendarIDs.insert(id)
        }
    }

    private func toggleSummaryReminderCalendar(id: String) {
        if settingsManager.journalSummaryReminderCalendarIDs.contains(id) {
            settingsManager.journalSummaryReminderCalendarIDs.remove(id)
        } else {
            settingsManager.journalSummaryReminderCalendarIDs.insert(id)
        }
    }
}
