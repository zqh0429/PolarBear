import Combine
import Foundation

enum LLMMode: String, CaseIterable, Identifiable {
    case `default` = "Default (Local)"
    case custom = "Custom"

    var id: String { self.rawValue }
}

enum SummaryDuration: String, CaseIterable, Identifiable, Codable {
    case oneDay = "1 Day"
    case threeDays = "3 Days"
    case oneWeek = "1 Week"

    var id: String { self.rawValue }

    var days: Int {
        switch self {
        case .oneDay: return 1
        case .threeDays: return 3
        case .oneWeek: return 7
        }
    }
}

class LLMSettingsManager: ObservableObject {
    @Published var mode: LLMMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "LLMMode")
        }
    }

    @Published var customURL: String {
        didSet {
            UserDefaults.standard.set(customURL, forKey: "LLMCustomURL")
        }
    }

    @Published var customAPIKey: String {
        didSet {
            UserDefaults.standard.set(customAPIKey, forKey: "LLMCustomAPIKey")
        }
    }

    @Published var customModel: String {
        didSet {
            UserDefaults.standard.set(customModel, forKey: "LLMCustomModel")
        }
    }

    @Published var showDebugOutput: Bool {
        didSet {
            UserDefaults.standard.set(showDebugOutput, forKey: "ShowDebugOutput")
        }
    }

    @Published var summaryDuration: SummaryDuration {
        didSet {
            UserDefaults.standard.set(summaryDuration.rawValue, forKey: "SummaryDuration")
        }
    }

    @Published var summaryCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(summaryCalendarIDs), forKey: "SummaryCalendarIDs")
        }
    }

    @Published var journalSummaryDuration: SummaryDuration {
        didSet {
            UserDefaults.standard.set(
                journalSummaryDuration.rawValue, forKey: "JournalSummaryDuration")
        }
    }

    @Published var journalSummaryCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(journalSummaryCalendarIDs), forKey: "JournalSummaryCalendarIDs")
        }
    }

    @Published var summaryReminderCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(summaryReminderCalendarIDs), forKey: "SummaryReminderCalendarIDs")
        }
    }

    @Published var journalSummaryReminderCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(journalSummaryReminderCalendarIDs),
                forKey: "JournalSummaryReminderCalendarIDs")
        }
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: "LLMMode") ?? LLMMode.default.rawValue
        self.mode = LLMMode(rawValue: savedMode) ?? .default

        self.customURL = UserDefaults.standard.string(forKey: "LLMCustomURL") ?? ""
        self.customAPIKey = UserDefaults.standard.string(forKey: "LLMCustomAPIKey") ?? ""
        self.customModel =
            UserDefaults.standard.string(forKey: "LLMCustomModel") ?? "qwen-long-latest"
        self.showDebugOutput = UserDefaults.standard.bool(forKey: "ShowDebugOutput")

        let savedDuration =
            UserDefaults.standard.string(forKey: "SummaryDuration")
            ?? SummaryDuration.oneDay.rawValue
        self.summaryDuration = SummaryDuration(rawValue: savedDuration) ?? .oneDay

        if let savedCalendarIDs = UserDefaults.standard.array(forKey: "SummaryCalendarIDs")
            as? [String]
        {
            self.summaryCalendarIDs = Set(savedCalendarIDs)
        } else {
            self.summaryCalendarIDs = []
        }

        if let savedSummaryReminderIDs = UserDefaults.standard.array(
            forKey: "SummaryReminderCalendarIDs") as? [String]
        {
            self.summaryReminderCalendarIDs = Set(savedSummaryReminderIDs)
        } else {
            self.summaryReminderCalendarIDs = []
        }

        let savedJournalDuration =
            UserDefaults.standard.string(forKey: "JournalSummaryDuration")
            ?? SummaryDuration.oneDay.rawValue
        self.journalSummaryDuration = SummaryDuration(rawValue: savedJournalDuration) ?? .oneDay

        if let savedJournalCalendarIDs = UserDefaults.standard.array(
            forKey: "JournalSummaryCalendarIDs")
            as? [String]
        {
            self.journalSummaryCalendarIDs = Set(savedJournalCalendarIDs)
        } else {
            self.journalSummaryCalendarIDs = []
        }

        if let savedJournalReminderIDs = UserDefaults.standard.array(
            forKey: "JournalSummaryReminderCalendarIDs") as? [String]
        {
            self.journalSummaryReminderCalendarIDs = Set(savedJournalReminderIDs)
        } else {
            self.journalSummaryReminderCalendarIDs = []
        }
    }

    var currentURL: URL? {
        switch mode {
        case .default:
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        case .custom:
            return URL(string: customURL)
        }
    }

    var currentAPIKey: String {
        switch mode {
        case .default:
            return "sk-d77631691a6541b4aa7bb6ccf0d2d866"
        case .custom:
            return customAPIKey
        }
    }

    var currentModel: String {
        switch mode {
        case .default:
            return "qwen-long-latest"
        case .custom:
            return customModel.isEmpty ? "qwen-long-latest" : customModel
        }
    }
}
