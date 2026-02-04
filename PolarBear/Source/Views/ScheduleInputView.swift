import EventKit
import PhotosUI
import SwiftUI

struct ScheduleInputView: View {
    @State private var inputText: String = "明天去医院"
    @State private var debugOutput: String = ""
    @State private var parsedIntent: ScheduleIntent?
    @State private var isAnalyzing = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    @State private var summaryText: String = ""
    @State private var isGeneratingSummary = false

    @ObservedObject var settingsManager: LLMSettingsManager

    // Use OpenAILLMService with dynamic settings
    var llmService: LLMServiceProtocol {
        guard let url = settingsManager.currentURL else {
            // Fallback or error handling if URL is invalid
            return OpenAILLMService(url: URL(string: "http://localhost")!, apiKey: "")
        }
        return OpenAILLMService(
            url: url, apiKey: settingsManager.currentAPIKey, model: settingsManager.currentModel)
    }

    @ObservedObject var calendarManager: CalendarManager

    init(calendarManager: CalendarManager = CalendarManager(), settingsManager: LLMSettingsManager)
    {
        self.calendarManager = calendarManager
        self.settingsManager = settingsManager
    }

    var body: some View {
        NavigationView {
            VStack {
                // Removed local API Key field as it's now in Settings

                if settingsManager.mode == .default {
                    Text("Using Default Server")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Text("Using Custom Server")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Text("Describe your event")
                    .font(.headline)
                    .padding(.top)

                if isGeneratingSummary {
                    Text("Generating schedule summary...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.bottom, 4)
                } else if !summaryText.isEmpty {
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                TextEditor(text: $inputText)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .padding()
                    .frame(height: 100)

                // Image Picker Section
                HStack {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .cornerRadius(8)
                            .overlay(
                                Button(action: {
                                    self.selectedImage = nil
                                    self.selectedItem = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(4),
                                alignment: .topTrailing
                            )
                    }

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(
                            selectedImage == nil ? "Select Image" : "Change Image",
                            systemImage: "photo"
                        )
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                                let image = UIImage(data: data)
                            {
                                selectedImage = image
                            }
                        }
                    }
                }
                .padding(.horizontal)

                if isAnalyzing {
                    ProgressView("Analyzing...")
                }

                Button(action: analyzeText) {
                    Text("Analyze")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
                .disabled(
                    (inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && selectedImage == nil) || isAnalyzing
                )

                if settingsManager.showDebugOutput && !debugOutput.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Debug Output:")
                            .font(.caption)
                            .bold()
                        ScrollView {
                            Text(debugOutput)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(5)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(5)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }

                Spacer()
            }
            .navigationTitle("New Event")
            .sheet(isPresented: $showingConfirmation) {
                if parsedIntent != nil {
                    ConfirmationView(
                        intent: Binding(
                            get: { parsedIntent! },
                            set: { parsedIntent = $0 }
                        ),
                        calendarManager: calendarManager,
                        isPresented: $showingConfirmation
                    )
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onAppear {
            generateSummary()
        }
    }

    func generateSummary() {
        guard !isGeneratingSummary else { return }
        isGeneratingSummary = true

        let duration = settingsManager.summaryDuration
        var calendarIDs: Set<String>? = nil
        if !settingsManager.summaryCalendarIDs.isEmpty {
            calendarIDs = settingsManager.summaryCalendarIDs
        }

        var reminderCalendarIDs: Set<String>? = nil
        if !settingsManager.summaryReminderCalendarIDs.isEmpty {
            reminderCalendarIDs = settingsManager.summaryReminderCalendarIDs
        }

        let events = calendarManager.fetchEvents(for: duration, calendarIDs: calendarIDs)

        // Fetch reminders asynchronously
        Task {
            let reminders = await calendarManager.fetchReminders(
                for: duration, calendarIDs: reminderCalendarIDs)

            if events.isEmpty && reminders.isEmpty {
                DispatchQueue.main.async {
                    self.summaryText =
                        "No upcoming events or reminders found for the next \(duration.rawValue)."
                    self.isGeneratingSummary = false
                }
                return
            }

            var scheduleText = events.map { event in
                let date = DateFormatter.localizedString(
                    from: event.startDate, dateStyle: .short, timeStyle: .none)
                let time = DateFormatter.localizedString(
                    from: event.startDate, dateStyle: .none, timeStyle: .short)
                return "- [Event] [\(date)] \(time): \(event.title ?? "Event")"
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

            do {
                let summary = try await llmService.generateScheduleSummary(
                    scheduleText: scheduleText)
                DispatchQueue.main.async {
                    self.summaryText = summary
                    self.isGeneratingSummary = false
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to generate summary: \(error.localizedDescription)")
                    self.summaryText = "Could not generate summary."
                    self.isGeneratingSummary = false
                }
            }
        }
    }

    func analyzeText() {
        isAnalyzing = true
        errorMessage = nil
        debugOutput = ""

        Task {
            do {
                let (intent, rawResponse) = try await llmService.parse(
                    text: inputText, image: selectedImage)
                DispatchQueue.main.async {
                    self.parsedIntent = intent
                    self.debugOutput = rawResponse

                    if intent.type == .delete {
                        do {
                            let result = try calendarManager.deleteEvent(from: intent)
                            self.errorMessage = result
                        } catch {
                            self.errorMessage = error.localizedDescription
                        }
                    } else if intent.type == .modify {
                        do {
                            let result = try calendarManager.modifyEvent(from: intent)
                            self.errorMessage = result
                        } catch {
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.showingConfirmation = true
                    }
                    self.isAnalyzing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to parse: \(error.localizedDescription)"
                    self.isAnalyzing = false
                }
            }
        }
    }
}

struct ConfirmationView: View {
    @Binding var intent: ScheduleIntent
    @ObservedObject var calendarManager: CalendarManager
    @Binding var isPresented: Bool
    @State private var successMessage: String?
    @State private var selectedCalendarID: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Title", text: $intent.title)

                    Picker("Type", selection: $intent.target) {
                        ForEach(ScheduleTarget.allCases, id: \.self) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }

                    Toggle("All Day", isOn: $intent.isAllDay)

                    if intent.target == .event {
                        if intent.isAllDay {
                            DatePicker(
                                "Date", selection: $intent.startDate, displayedComponents: .date)
                        } else {
                            DatePicker("Start", selection: $intent.startDate)
                            DatePicker("End", selection: $intent.endDate)
                        }
                    } else {
                        // Reminder
                        if intent.isAllDay {
                            DatePicker(
                                "Due Date", selection: $intent.startDate, displayedComponents: .date
                            )
                        } else {
                            DatePicker("Due Date", selection: $intent.startDate)
                        }
                    }

                    if let location = intent.location, intent.target == .event {
                        TextField(
                            "Location",
                            text: Binding(
                                get: { intent.location ?? "" },
                                set: { intent.location = $0 }
                            ))
                    }

                    TextField(
                        "Notes",
                        text: Binding(
                            get: { intent.notes ?? "" },
                            set: { intent.notes = $0 }
                        ))
                }

                if intent.target == .event {
                    Section(header: Text("Calendar")) {
                        Picker("Save to", selection: $selectedCalendarID) {
                            Text("Default").tag(String?.none)
                            ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) {
                                calendar in
                                Text(calendar.title).tag(String?.some(calendar.calendarIdentifier))
                            }
                        }
                    }
                } else {
                    Section(header: Text("Reminder List")) {
                        Picker("Save to", selection: $selectedCalendarID) {
                            Text("Default").tag(String?.none)
                            ForEach(
                                calendarManager.availableReminderCalendars, id: \.calendarIdentifier
                            ) {
                                calendar in
                                Text(calendar.title).tag(String?.some(calendar.calendarIdentifier))
                            }
                        }
                    }
                }

                Section {
                    Button(intent.target == .event ? "Add Event" : "Add Reminder") {
                        addToCalendar()
                    }
                }

                if let message = successMessage {
                    Section {
                        Text(message)
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Confirm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                // Pre-select default calendar if set
                if intent.target == .event {
                    if let defaultID = calendarManager.defaultCalendarID {
                        selectedCalendarID = defaultID
                    }
                } else {
                    if let defaultID = calendarManager.defaultReminderCalendarID {
                        selectedCalendarID = defaultID
                    }
                }
            }
        }
    }

    func addToCalendar() {
        do {
            if intent.target == .event {
                var targetCalendar: EKCalendar? = nil
                if let id = selectedCalendarID,
                    let found = calendarManager.availableCalendars.first(where: {
                        $0.calendarIdentifier == id
                    })
                {
                    targetCalendar = found
                }
                try calendarManager.addEvent(from: intent, to: targetCalendar)
                successMessage = "Event added successfully!"
            } else {
                var targetCalendar: EKCalendar? = nil
                if let id = selectedCalendarID,
                    let found = calendarManager.availableReminderCalendars.first(where: {
                        $0.calendarIdentifier == id
                    })
                {
                    targetCalendar = found
                }
                try calendarManager.addReminder(from: intent, to: targetCalendar)
                successMessage = "Reminder added successfully!"
            }

            // Auto close after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isPresented = false
            }
        } catch {
            successMessage = "Error: \(error.localizedDescription)"
        }
    }
}
