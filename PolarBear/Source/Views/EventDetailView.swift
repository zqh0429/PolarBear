import EventKit
import SwiftUI

struct EventDetailView: View {
    let event: EKEvent
    @ObservedObject var calendarManager: CalendarManager
    @Environment(\.presentationMode) var presentationMode

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedIsAllDay: Bool = false
    @State private var editedStartDate: Date = Date()
    @State private var editedEndDate: Date = Date()
    @State private var editedLocation: String = ""
    @State private var editedNotes: String = ""

    var body: some View {
        Form {
            if isEditing {
                Section(header: Text("Edit Details")) {
                    TextField("Title", text: $editedTitle)
                    Toggle("All Day", isOn: $editedIsAllDay)

                    if !editedIsAllDay {
                        DatePicker("Start", selection: $editedStartDate)
                        DatePicker("End", selection: $editedEndDate)
                    } else {
                        DatePicker("Date", selection: $editedStartDate, displayedComponents: .date)
                    }

                    TextField("Location", text: $editedLocation)
                    TextEditor(text: $editedNotes)
                        .frame(height: 100)
                }
            } else {
                Section(header: Text("Event Details")) {
                    Text(event.title)
                        .font(.headline)

                    if event.isAllDay {
                        let isSingleDay = Calendar.current.isDate(
                            event.endDate,
                            inSameDayAs: Calendar.current.date(
                                byAdding: .day, value: 1, to: event.startDate)!)

                        if isSingleDay {
                            HStack {
                                Text("All Day")
                                Spacer()
                                Text(event.startDate, style: .date)
                            }
                        } else {
                            // Multi-day all day
                            HStack {
                                Text("All Day")
                                Spacer()
                                Text("Yes")
                            }
                            HStack {
                                Text("Start")
                                Spacer()
                                Text(event.startDate, style: .date)
                            }
                            HStack {
                                Text("End")
                                Spacer()
                                let inclusiveEnd = event.endDate.addingTimeInterval(-1)
                                Text(inclusiveEnd, style: .date)
                            }
                        }
                    } else {
                        HStack {
                            Text("Start")
                            Spacer()
                            Text(event.startDate, style: .date)
                            Text(event.startDate, style: .time)
                        }
                        HStack {
                            Text("End")
                            Spacer()
                            Text(event.endDate, style: .date)
                            Text(event.endDate, style: .time)
                        }
                    }

                    if let location = event.location, !location.isEmpty {
                        HStack {
                            Text("Location")
                            Spacer()
                            Text(location)
                                .foregroundColor(.blue)
                        }
                    }

                    if let notes = event.notes, !notes.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Notes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(notes)
                                .font(.body)
                        }
                    }

                    if let calendar = event.calendar {
                        HStack {
                            Text("Calendar")
                            Spacer()
                            Text(calendar.title)
                                .foregroundColor(Color(calendar.cgColor))
                        }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Event" : "Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }
            }
        }
    }

    func startEditing() {
        editedTitle = event.title
        editedIsAllDay = event.isAllDay
        editedStartDate = event.startDate
        editedEndDate = event.endDate
        editedLocation = event.location ?? ""
        editedNotes = event.notes ?? ""
        isEditing = true
    }

    func saveChanges() {
        event.title = editedTitle
        event.isAllDay = editedIsAllDay
        event.startDate = editedStartDate
        event.endDate = editedEndDate
        event.location = editedLocation
        event.notes = editedNotes

        do {
            try calendarManager.saveEvent(event)
            isEditing = false
        } catch {
            print("Error saving event: \(error.localizedDescription)")
            // Optionally handle error alert here
        }
    }
}
