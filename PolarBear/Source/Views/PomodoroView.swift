import Charts
import Combine
import SwiftUI

class PomodoroViewModel: ObservableObject {
    @Published var timeRemaining: Int = 25 * 60
    @Published var isRunning: Bool = false
    @Published var isBreak: Bool = false
    @Published var totalSessions: Int = 0

    @Published var focusDuration: Int = 25 {
        didSet {
            if !isRunning && !isBreak {
                timeRemaining = focusDuration * 60
            }
        }
    }

    @Published var currentTaskName: String = ""
    @Published var taskQueue: [FocusTask] = []
    @Published var isPlanActive: Bool = false
    @Published var currentPlanId: UUID?
    @Published var currentPlanName: String = ""
    @Published var showConfetti: Bool = false

    private var timer: AnyCancellable?
    private let historyManager = FocusHistoryManager.shared

    var progress: CGFloat {
        let totalTime = isBreak ? 5 * 60 : focusDuration * 60
        return CGFloat(timeRemaining) / CGFloat(totalTime)
    }

    func startTimer() {
        isRunning = true
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink {
            [weak self] _ in
            self?.tick()
        }
    }

    func pauseTimer() {
        isRunning = false
        timer?.cancel()
    }

    func resetTimer() {
        pauseTimer()
        isBreak = false
        if isPlanActive, let first = taskQueue.first {
            focusDuration = first.durationMinutes
            currentTaskName = first.name
        }
        timeRemaining = focusDuration * 60
        showConfetti = false
    }

    func skipContent() {
        pauseTimer()
        if isBreak {
            // End break, start next focus
            isBreak = false
            if isPlanActive {
                startNextTaskInPlan()
            } else {
                timeRemaining = focusDuration * 60
            }
        } else {
            // End focus session
            saveSession()

            // Start break
            isBreak = true
            timeRemaining = 5 * 60
            totalSessions += 1

            if isPlanActive {
                // Remove completed task
                if !taskQueue.isEmpty {
                    taskQueue.removeFirst()
                }

                if taskQueue.isEmpty {
                    completePlan()
                }
            }
        }
    }

    private func startNextTaskInPlan() {
        if let nextTask = taskQueue.first {
            focusDuration = nextTask.durationMinutes
            currentTaskName = nextTask.name
            timeRemaining = focusDuration * 60
        } else {
            completePlan()
        }
    }

    private func completePlan() {
        isPlanActive = false
        isBreak = false
        currentPlanId = nil
        currentPlanName = ""
        currentTaskName = ""
        focusDuration = 25
        timeRemaining = 25 * 60
        showConfetti = true
    }

    private func saveSession() {
        let savedName =
            isPlanActive
            ? currentTaskName : (currentTaskName.isEmpty ? "Untitled" : currentTaskName)
        historyManager.saveSession(
            duration: focusDuration * 60, taskName: savedName, planId: currentPlanId,
            planName: isPlanActive ? currentPlanName : nil)
    }

    private func tick() {
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            skipContent()
        }
    }

    func timeString() -> String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // Plan Management
    func startPlan(tasks: [FocusTask], name: String) {
        guard !tasks.isEmpty else { return }
        taskQueue = tasks
        isPlanActive = true
        currentPlanId = UUID()
        currentPlanName = name
        startNextTaskInPlan()
        isBreak = false
        showConfetti = false
    }
}

struct PomodoroView: View {
    @StateObject private var viewModel = PomodoroViewModel()
    @State private var showingPlanSheet = false
    @State private var showingHistorySheet = false

    let availableDurations = [15, 20, 25, 30, 45, 60]

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 30) {
                    // Top Bar
                    HStack {
                        Button(action: { showingHistorySheet = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Spacer()
                        Button(action: { showingPlanSheet = true }) {
                            Image(systemName: "list.bullet.clipboard")
                        }
                    }
                    .padding(.horizontal)
                    .font(.title2)

                    // Status
                    Text(
                        viewModel.isBreak
                            ? "Break Time" : (viewModel.isPlanActive ? "Focus Plan" : "Focus Time")
                    )
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.isBreak ? .green : .blue)

                    if viewModel.isPlanActive && !viewModel.currentPlanName.isEmpty {
                        Text(viewModel.currentPlanName)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    // Timer Circle
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 20)
                            .opacity(0.3)
                            .foregroundColor(Color.gray)

                        Circle()
                            .trim(from: 0.0, to: viewModel.progress)
                            .stroke(
                                style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                            )
                            .foregroundColor(viewModel.isBreak ? .green : .blue)
                            .rotationEffect(Angle(degrees: 270.0))
                            .animation(.linear, value: viewModel.progress)

                        VStack {
                            Text(viewModel.timeString())
                                .font(.system(size: 60, weight: .bold, design: .monospaced))

                            if viewModel.isPlanActive {
                                Text(viewModel.currentTaskName)
                                    .font(.headline)
                                    .padding(.top, 5)
                                Text("Queue: \(viewModel.taskQueue.count) left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if !viewModel.isBreak {
                                TextField("Current Task", text: $viewModel.currentTaskName)
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 200)
                                    .padding(.top, 10)
                            }
                        }
                    }
                    .padding(.horizontal, 40)

                    // Duration Picker (Only when not running and not in plan)
                    if !viewModel.isRunning && !viewModel.isBreak && !viewModel.isPlanActive {
                        HStack {
                            Text("Duration:")
                            Picker("Duration", selection: $viewModel.focusDuration) {
                                ForEach(availableDurations, id: \.self) { duration in
                                    Text("\(duration) min").tag(duration)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }

                    // Controls
                    HStack(spacing: 30) {
                        Button(action: {
                            viewModel.resetTimer()
                        }) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.gray)
                        }

                        Button(action: {
                            if viewModel.isRunning {
                                viewModel.pauseTimer()
                            } else {
                                viewModel.startTimer()
                            }
                        }) {
                            Image(
                                systemName: viewModel.isRunning
                                    ? "pause.circle.fill" : "play.circle.fill"
                            )
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(viewModel.isBreak ? .green : .blue)
                        }

                        Button(action: {
                            viewModel.skipContent()
                        }) {
                            Image(systemName: "forward.end.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
                        }
                    }

                    Text("Total Sessions Today: \(viewModel.totalSessions)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 10)

                    Spacer()
                }
                .navigationTitle("Pomodoro")
                .navigationBarHidden(true)
                .sheet(isPresented: $showingPlanSheet) {
                    FocusPlanView(viewModel: viewModel, isPresented: $showingPlanSheet)
                }
                .sheet(isPresented: $showingHistorySheet) {
                    FocusHistoryView(isPresented: $showingHistorySheet)
                }

                if viewModel.showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                viewModel.showConfetti = false
                            }
                        }
                }
            }
        }
    }
}

struct FocusPlanView: View {
    @ObservedObject var viewModel: PomodoroViewModel
    @Binding var isPresented: Bool

    @State private var planName: String = ""
    @State private var tasks: [FocusTask] = []
    @State private var newTaskName: String = ""
    @State private var newTaskDuration: Int = 25

    let availableDurations = [15, 20, 25, 30, 45, 60]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Plan Details")) {
                    TextField("Plan Name (Optional)", text: $planName)
                }

                Section(header: Text("New Task")) {
                    TextField("Task Name", text: $newTaskName)
                    Picker("Duration", selection: $newTaskDuration) {
                        ForEach(availableDurations, id: \.self) { duration in
                            Text("\(duration) min").tag(duration)
                        }
                    }
                    Button("Add to Plan") {
                        guard !newTaskName.isEmpty else { return }
                        let task = FocusTask(name: newTaskName, durationMinutes: newTaskDuration)
                        tasks.append(task)
                        newTaskName = ""
                    }
                    .disabled(newTaskName.isEmpty)
                }

                Section(header: Text("Plan (\(tasks.count) tasks)")) {
                    ForEach(tasks) { task in
                        HStack {
                            Text(task.name)
                            Spacer()
                            Text("\(task.durationMinutes) min")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        tasks.remove(atOffsets: indexSet)
                    }
                }

                Section {
                    Button("Start Plan") {
                        viewModel.startPlan(tasks: tasks, name: planName)
                        isPresented = false
                    }
                    .disabled(tasks.isEmpty)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Create Focus Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// ... (existing imports and PomodoroViewModel)

// Update FocusHistoryView
struct FocusHistoryView: View {
    @Binding var isPresented: Bool
    @StateObject private var historyManager = FocusHistoryManager.shared
    @State private var selectedTab = 0
    @State private var editingItemId: UUID?
    @State private var editingPlanId: UUID?
    @State private var newName: String = ""
    @State private var showRenameAlert = false

    var body: some View {
        NavigationView {
            VStack {
                Picker("View Mode", selection: $selectedTab) {
                    Text("Log").tag(0)
                    Text("Charts").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                if selectedTab == 0 {
                    HistoryListView(
                        historyManager: historyManager,
                        editingItemId: $editingItemId,
                        editingPlanId: $editingPlanId,
                        newName: $newName,
                        showRenameAlert: $showRenameAlert
                    )
                } else {
                    StatisticsView(historyManager: historyManager)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .alert("Rename", isPresented: $showRenameAlert) {
                TextField("New Name", text: $newName)
                Button("Cancel", role: .cancel) {
                    editingItemId = nil
                    editingPlanId = nil
                }
                Button("Save") {
                    if let id = editingItemId {
                        historyManager.renameSession(id: id, newName: newName)
                    } else if let planId = editingPlanId {
                        historyManager.renamePlan(planId: planId, newName: newName)
                    }
                    editingItemId = nil
                    editingPlanId = nil
                }
            }
        }
    }
}

struct HistoryListView: View {
    @ObservedObject var historyManager: FocusHistoryManager
    @Binding var editingItemId: UUID?
    @Binding var editingPlanId: UUID?
    @Binding var newName: String
    @Binding var showRenameAlert: Bool

    var body: some View {
        List {
            ForEach(groupedHistory(), id: \.id) { group in
                if group.isPlan {
                    DisclosureGroup(
                        content: {
                            ForEach(group.sessions) { session in
                                SessionRow(session: session)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            historyManager.deleteSession(id: session.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            editingItemId = session.id
                                            newName = session.taskName ?? ""
                                            showRenameAlert = true
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                            }
                        },
                        label: {
                            HStack {
                                Text(group.sessions.first?.planName ?? "Focus Plan")
                                    .font(.headline)
                                Spacer()
                                Text("\(group.sessions.count) tasks")
                                    .foregroundColor(.secondary)
                            }
                            .contextMenu {
                                Button {
                                    if let planId = group.sessions.first?.planId {
                                        editingPlanId = planId
                                        newName = group.sessions.first?.planName ?? ""
                                        showRenameAlert = true
                                    }
                                } label: {
                                    Label("Rename Plan", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    if let planId = group.sessions.first?.planId {
                                        historyManager.deletePlan(planId: planId)
                                    }
                                } label: {
                                    Label("Delete Plan", systemImage: "trash")
                                }
                            }
                        }
                    )
                } else {
                    if let session = group.sessions.first {
                        SessionRow(session: session)
                            .swipeActions {
                                Button(role: .destructive) {
                                    historyManager.deleteSession(id: session.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingItemId = session.id
                                    newName = session.taskName ?? ""
                                    showRenameAlert = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
        }
    }

    struct HistoryGroup: Identifiable {
        let id = UUID()
        let isPlan: Bool
        let sessions: [FocusSession]
    }

    func groupedHistory() -> [HistoryGroup] {
        var groups: [HistoryGroup] = []
        let reversedHistory = historyManager.history.reversed()
        var currentPlanId: UUID?
        var currentPlanSessions: [FocusSession] = []

        for session in reversedHistory {
            if let planId = session.planId {
                if currentPlanId == planId {
                    currentPlanSessions.append(session)
                } else {
                    if !currentPlanSessions.isEmpty {
                        groups.append(
                            HistoryGroup(isPlan: true, sessions: currentPlanSessions))
                    }
                    currentPlanId = planId
                    currentPlanSessions = [session]
                }
            } else {
                if !currentPlanSessions.isEmpty {
                    groups.append(HistoryGroup(isPlan: true, sessions: currentPlanSessions))
                    currentPlanSessions = []
                    currentPlanId = nil
                }
                groups.append(HistoryGroup(isPlan: false, sessions: [session]))
            }
        }
        if !currentPlanSessions.isEmpty {
            groups.append(HistoryGroup(isPlan: true, sessions: currentPlanSessions))
        }
        return groups
    }
}

struct StatisticsView: View {
    @ObservedObject var historyManager: FocusHistoryManager
    @State private var startDate = Date()
    @State private var endDate = Date()

    // Grouping State
    @State private var groupPlans: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Daily Focus Bar Chart
                VStack(alignment: .leading) {
                    Text("Daily Focus (Last 7 Days)")
                        .font(.headline)
                        .padding(.bottom, 5)

                    if #available(iOS 16.0, *) {
                        Chart {
                            ForEach(historyManager.getLast7DaysDailyFocus(), id: \.date) { item in
                                BarMark(
                                    x: .value("Date", item.date, unit: .day),
                                    y: .value("Minutes", item.minutes)
                                )
                                .foregroundStyle(Color.blue.gradient)
                            }
                        }
                        .frame(height: 200)
                    } else {
                        Text("Charts require iOS 16.0 or newer")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Task Distribution Pie Chart
                VStack(alignment: .leading) {
                    HStack {
                        Text("Task Distribution")
                            .font(.headline)
                        Spacer()
                        // Toggle for grouping plans
                        Toggle("Group Plans", isOn: $groupPlans)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                        Text("Group Plans")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 5)

                    HStack {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                        Text("-")
                        DatePicker("End", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(.bottom, 10)

                    if #available(iOS 17.0, *) {
                        let data = historyManager.getFlexibleDistribution(
                            startDate: startDate, endDate: endDate, groupPlans: groupPlans)

                        if data.isEmpty {
                            Text("No focus data for this period")
                                .foregroundColor(.secondary)
                                .frame(height: 250)
                                .frame(maxWidth: .infinity)
                        } else {
                            Chart(data) { item in
                                SectorMark(
                                    angle: .value("Minutes", item.minutes),
                                    innerRadius: .ratio(0.5),
                                    angularInset: 1.5
                                )
                                .cornerRadius(5)
                                .foregroundStyle(by: .value("Name", item.name))
                            }
                            .frame(height: 250)
                        }
                    } else {
                        // Fallback for iOS 16
                        Chart(
                            historyManager.getFlexibleDistribution(
                                startDate: startDate, endDate: endDate, groupPlans: groupPlans)
                        ) { item in
                            BarMark(
                                x: .value("Minutes", item.minutes),
                                y: .value("Name", item.name)
                            )
                            .foregroundStyle(by: .value("Name", item.name))
                        }
                        .frame(height: 250)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

struct SessionRow: View {
    let session: FocusSession

    // Create a precise date formatter
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.taskName ?? "Untitled")
                    .font(.headline)
                Text(session.date, formatter: SessionRow.dateFormatter)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(session.durationBytes / 60) min")
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct ConfettiView: View {
    let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<50) { _ in
                Circle()
                    .fill(colors.randomElement()!)
                    .frame(width: CGFloat.random(in: 5...10), height: CGFloat.random(in: 5...10))
                    .position(
                        x: CGFloat.random(in: 0...geometry.size.width),
                        y: CGFloat.random(in: 0...geometry.size.height)
                    )
                    .offset(y: CGFloat.random(in: -geometry.size.height...0))
                    .animation(
                        Animation.linear(duration: Double.random(in: 2...4))
                            .repeatForever(autoreverses: false),
                        value: UUID()
                    )
            }
        }
    }
}

#Preview {
    PomodoroView()
}
