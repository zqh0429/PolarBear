import EventKit
import SwiftUI
import UIKit

struct MonthCalendarView: UIViewRepresentable {
    @ObservedObject var calendarManager: CalendarManager
    @Binding var selectedDate: Date?

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.locale = Locale.current
        calendarView.fontDesign = .default

        // Set the selection behavior
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.selectionBehavior = selection

        // set delegate for decorations
        calendarView.delegate = context.coordinator

        // Set visible date to current if available
        // Note: visibleDateComponents is not directly settable in init easily in all cases,
        // but UICalendarView defaults to 'now'.

        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        // Reload decorations when events change
        // We can optimize this by identifying specific dates, but reloading all for now is safer
        let datesToReload = context.coordinator.datesWithEvents
        uiView.reloadDecorations(forDateComponents: datesToReload, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: MonthCalendarView
        var datesWithEvents: [DateComponents] = []

        init(_ parent: MonthCalendarView) {
            self.parent = parent
        }

        // MARK: - UICalendarSelectionSingleDateDelegate

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents = dateComponents,
                let date = Calendar.current.date(from: dateComponents)
            else {
                parent.selectedDate = nil
                return
            }
            parent.selectedDate = date
        }

        // MARK: - UICalendarViewDelegate

        func calendarView(
            _ calendarView: UICalendarView, decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            // Check if there are events on this date
            guard let date = Calendar.current.date(from: dateComponents) else { return nil }

            // Filter events for this day
            // We need to check parent.calendarManager.events
            // Using a simple filter here might be slow if many events, but should be okay for phone

            let dayStart = Calendar.current.startOfDay(for: date)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

            // Find valid event for this day to get color
            let matchingEvent = parent.calendarManager.events.first { event in
                return event.startDate < dayEnd && event.endDate > dayStart
            }

            if let event = matchingEvent {
                return .default(color: UIColor(cgColor: event.calendar.cgColor), size: .small)
            }

            return nil
        }
    }
}
