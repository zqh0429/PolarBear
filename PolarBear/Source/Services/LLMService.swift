import Foundation
import UIKit

protocol LLMServiceProtocol {
    func parse(text: String, image: UIImage?) async throws -> (ScheduleIntent, String)
    func summarize(scheduleText: String) async throws -> String
    func generateScheduleSummary(scheduleText: String) async throws -> String
}

class MockLLMService: LLMServiceProtocol {
    func parse(text: String, image: UIImage?) async throws -> (ScheduleIntent, String) {
        // ... (existing implementation)
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        let now = Date()
        let calendar = Calendar.current

        // Ensure "tomorrow" is actually calculated based on now
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow),
            let end = calendar.date(byAdding: .hour, value: 1, to: start)
        else {
            throw NSError(
                domain: "MockLLMService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to calculate dates"])
        }

        return (
            ScheduleIntent(
                title: "Mock Event: " + text.prefix(20),
                startDate: start,
                endDate: end,
                location: "Virtual",
                notes: "Parsed from: \(text)"
            ), "Mock Raw JSON Response for: \(text)"
        )
    }

    func summarize(scheduleText: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        return "This is a mock summary of your schedule. You have a busy day!"
    }

    func generateScheduleSummary(scheduleText: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        return "You have 3 events today starting with meeting at 9am. It looks like a balanced day."
    }
}

class OpenAILLMService: LLMServiceProtocol {
    private let apiKey: String
    private let url: URL
    private let model: String

    init(url: URL, apiKey: String, model: String = "qwen-long-latest") {
        self.url = url
        self.apiKey = apiKey
        self.model = model
    }

    func summarize(scheduleText: String) async throws -> String {
        let systemPrompt = """
            You are a helpful personal assistant.
            The user will provide a list of calendar events for a specific day.
            Your task is to write a concise, reflective, and encouraging summary of this day's schedule, suitable for a personal journal entry.
            Focus on the flow of the day, key events, and the overall "vibe".
            Keep it under 3-4 sentences.
            """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": scheduleText],
            ],
            "temperature": 0.7,  // Slightly higher creative temperature for summary
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "OpenAILLMService", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NSError(
                domain: "OpenAILLMService", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API Response Structure"])
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateScheduleSummary(scheduleText: String) async throws -> String {
        let systemPrompt = """
            You are a helpful personal assistant.
            The user will provide a list of calendar events.
            Your task is to write a strictly 2-sentence summary of the schedule.
            Focus on the most important events and the overall busyness.
            Do not list every single event.
            """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": scheduleText],
            ],
            "temperature": 0.5,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "OpenAILLMService", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NSError(
                domain: "OpenAILLMService", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API Response Structure"])
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parse(text: String, image: UIImage? = nil) async throws -> (ScheduleIntent, String) {
        // ... (existing implementation)
        let now = Date()
        // Use DateFormatter with local timezone to provide correct context
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.timeZone = TimeZone.current
        let nowString = dateFormatter.string(from: now)
        let timeZoneCode = TimeZone.current.abbreviation() ?? "Local Time"

        let systemPrompt = """
            You are a helpful assistant that parses natural language schedule requests into JSON.
            The current local date and time is: \(nowString) (\(timeZoneCode)).
            Output ONLY valid JSON matching this schema:
            {
              "ocr_content": "String: explicit transcription of all visible text in the image",
              "intent_type": "add" | "delete" | "modify",
              "target": "Event" | "Reminder",
              "title": "String",
              "start_time": "ISO8601 String (e.g. 2026-02-15T13:29:00+08:00)",
              "end_time": "ISO8601 String",
              "is_all_day": true | false,
              "location": "String or null",
              "notes": "String or null"
            }
            Do not include markdown formatting (like ```json), just the raw JSON string.
            IMPORTANT: Use the same timezone offset as the current time provided (\(nowString)).
            IMPORTANT: Always include seconds (e.g. :00) in timestamps.

            Decision Rules for "target":
            - If the user uses words like "remind me", "todo", "task", "buy", "checklist", set "target": "Reminder".
            - If it implies a meeting, appointment, specific time block, or "schedule", set "target": "Event".
            - Default to "Event" if unclear.

            If end_time is not specified:
              - If it IS an all-day event, use the same date as start_time.
              - If it is NOT all-day, assume 1 hour after start_time.
            If NO specific time is mentioned for a REMINDER (e.g. "Buy milk"), set "is_all_day": true, and start_time to 00:00:00 of tomorrow (or today if urgent).
            If NO specific time is mentioned for an EVENT (e.g. "Meeting"), set "is_all_day": true and set start_time to 00:00:00 of that day.

            For "delete" requests, infer the start_time based on context (e.g. "tomorrow morning") to help identify the event.
            For "modify" requests:
             - Use "title" to identify the EXISTING event/reminder to change.
             - Only include "start_time"/"end_time"/"location" if they are being CHANGED. If unchanged, try to estimate or keep them consistent with the original if known, otherwise provide best guess key.
            For negation (e.g. "Actually, I don't want to go", "Cancel that"): use "delete".
            For modification (e.g. "Change that to 2pm", "Move it to tomorrow"): use "modify".

            IMAGE PARSING INSTRUCTIONS:
            If an image is provided, you MUST perform OCR to extract details.
            0. **CRITICAL STEP**: First, fill the "ocr_content" field with EVERYTHING you can read from the image. This will help you find the dates.
            1. Look carefully for DATE and TIME information.
               - Train Tickets: Look for patterns like "02月15日" (Feb 15), "13:29" (Start), "18:45" (End).
               - Screenshots: Look for time headers or list items.
            2. If 'Year' is missing in the image, assume the *next occurrence* of that date relative to today (\(nowString)).
               - Example: If today is 2026-02-04 and image says "02月15日", assume "2026-02-15".
            3. Use the most prominent text as the 'title' if not specified in text (e.g., "深圳北 -> 宜春").
            4. Extract location (e.g. "Shenzhen North", "Meeting Room A") if visible.
            5. Even if the text prompt is empty, rely entirely on the image content.
            """

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
            let base64Image = imageData.base64EncodedString()
            let userContent: [Any] = [
                [
                    "type": "text",
                    "text": text.isEmpty ? "Parse the schedule from this image." : text,
                ],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64Image)"
                    ],
                ],
            ]
            messages.append(["role": "user", "content": userContent])
        } else {
            messages.append(["role": "user", "content": text])
        }

        let requestBody: [String: Any] = [
            "model": model,  // Ensure model supports vision (e.g. qwen-vl-max)
            "messages": messages,
            "temperature": 0.2,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "OpenAILLMService", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }

        // Parse OpenAI Response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NSError(
                domain: "OpenAILLMService", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API Response Structure"])
        }

        // Clean markdown code blocks if present (just in case)
        let cleanContent = content.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "").trimmingCharacters(
                in: .whitespacesAndNewlines)

        guard let intentData = cleanContent.data(using: .utf8),
            let jsonObject = try JSONSerialization.jsonObject(with: intentData) as? [String: Any]
        else {
            throw NSError(
                domain: "OpenAILLMService", code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to parse content as JSON: \(cleanContent)"
                ])
        }

        // Helper to parse date
        func parseDate(_ string: String?) -> Date? {
            guard let string = string else { return nil }

            // Try ISO8601 (Strict)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: string) { return date }

            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: string) { return date }

            // Try flexible custom formats
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Iterate common formats, including those without seconds
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                "yyyy-MM-dd'T'HH:mmZ",
                "yyyy-MM-dd'T'HH:mmXXXXX",
            ]

            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: string) { return date }
            }

            return nil
        }

        // Relaxed parsing
        let title =
            jsonObject["title"] as? String ?? (text.isEmpty ? "New Event" : text.prefix(20) + "...")

        let startTimeStr = jsonObject["start_time"] as? String
        let endTimeStr = jsonObject["end_time"] as? String

        // Default to start of tomorrow if parsing fails or missing
        let defaultDate =
            Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()

        let startDate = parseDate(startTimeStr) ?? defaultDate
        let endDate = parseDate(endTimeStr) ?? startDate.addingTimeInterval(3600)  // Default 1 hour duration

        let typeString = jsonObject["intent_type"] as? String ?? "add"
        var type: IntentType
        switch typeString {
        case "delete": type = .delete
        case "modify": type = .modify
        default: type = .add
        }

        let targetString = jsonObject["target"] as? String ?? "Event"
        let target: ScheduleTarget = (targetString == "Reminder") ? .reminder : .event

        let location = jsonObject["location"] as? String
        let notes = jsonObject["notes"] as? String
        let isAllDay = jsonObject["is_all_day"] as? Bool ?? false

        return (
            ScheduleIntent(
                type: type,
                target: target,
                title: title,
                startDate: startDate,
                endDate: endDate,
                location: location,
                notes: notes,
                isAllDay: isAllDay
            ), cleanContent
        )
    }
}
