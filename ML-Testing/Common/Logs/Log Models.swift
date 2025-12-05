//
//  LogModels.swift
//  ByoSync
//

import Foundation
import os.log

// MARK: - Log Type
enum LogType: String, Codable, Sendable {
    case middlewareCall = "MIDDLEWARE_CALL"
    case middlewareSuccess = "MIDDLEWARE_SUCCESS"
    case apiCall = "API_CALL"
    case badRequest = "BAD_REQUEST"
    case serverError = "SERVER_ERROR"
    case success = "SUCCESS"
}

// MARK: - Log Source
enum LogSource: String, Codable, Sendable {
    case app = "APP"
    case ml = "ML"
}

// MARK: - Backend Log Entry
struct BackendLogEntry: Codable, Sendable {
    let type: String
    let form: String  // "form" as per your API (though "from" would be grammatically correct)
    let message: String
    let timeTaken: String // Timestamp in milliseconds
    let user: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case form
        case message
        case timeTaken
        case user
    }
}

// MARK: - Log Create Response
struct LogCreateResponse: Decodable,Sendable {
    let success: Bool
    let message: String
    let statusCode: Int?
}

// MARK: - Internal Log Entry (for local storage)
struct InternalLogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let type: LogType
    let source: LogSource
    let level: LogLevel
    let message: String
    let timestamp: Date
    let file: String
    let function: String
    let line: Int
    let userId: String?
    let performanceTime: TimeInterval? // For tracking operation duration
    
    init(
        type: LogType,
        source: LogSource,
        level: LogLevel,
        message: String,
        timestamp: Date = Date(),
        file: String,
        function: String,
        line: Int,
        userId: String?,
        performanceTime: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.source = source
        self.level = level
        self.message = message
        self.timestamp = timestamp
        self.file = file
        self.function = function
        self.line = line
        self.userId = userId
        self.performanceTime = performanceTime
    }
    
    // Convert to backend format
    func toBackendFormat() -> BackendLogEntry {
        let fileName = (file as NSString).lastPathComponent
        let timestampMs = String(Int(timestamp.timeIntervalSince1970 * 1000))
        
        let fullMessage: String
        if let perfTime = performanceTime {
            fullMessage = """
            [\(level.icon) \(level.name)] \(message)
            📍 \(fileName):\(line) - \(function)
            ⏱️ Performance: \(String(format: "%.3f", perfTime))s
            """
        } else {
            fullMessage = """
            [\(level.icon) \(level.name)] \(message)
            📍 \(fileName):\(line) - \(function)
            """
        }
        
        return BackendLogEntry(
            type: type.rawValue,
            form: source.rawValue,
            message: fullMessage,
            timeTaken: timestampMs,
            user: userId ?? "unknown"
        )
    }
}

enum LogLevel: Int, Codable, Comparable, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5
    
    var icon: String {
        switch self {
        case .verbose: return "💬"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
    
    var name: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug: return .debug
        case .info: return .info
        case .warning, .error: return .error
        case .critical: return .fault
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
