//
//  ContentView.swift
//  PolarBear
//
//  Created by Dawnnn on 2026/2/2.
//

import SwiftUI

struct ContentView: View {
    // Create a shared instance of CalendarManager
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var settingsManager = LLMSettingsManager()
    @StateObject private var journalManager = JournalManager()

    var body: some View {
        TabView {
            // ScheduleInputView will need to be updated to accept calendarManager if it doesn't already allow injection
            ScheduleInputView(calendarManager: calendarManager, settingsManager: settingsManager)
                .tabItem {
                    Label("New Event", systemImage: "plus.circle")
                }

            CalendarDisplayView(calendarManager: calendarManager)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            JournalListView(
                journalManager: journalManager, calendarManager: calendarManager,
                settingsManager: settingsManager
            )
            .tabItem {
                Label("Journal", systemImage: "book.closed")
            }

            SettingsView(settingsManager: settingsManager, calendarManager: calendarManager)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

#Preview {
    ContentView()
}
