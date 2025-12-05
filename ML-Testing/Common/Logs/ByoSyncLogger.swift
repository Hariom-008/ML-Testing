import Foundation
import UIKit

final class Logger {
    
    // MARK: - Singleton
    static let shared = Logger()
    
    // MARK: - Configuration
    private let batchSize = 50 // Reduced from 50 for better performance with individual sends
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 5.0
    
    private var pendingLogs: [InternalLogEntry] = []
    private let queue = DispatchQueue(label: "com.byosync.logger", qos: .utility)
    private var isSending = false
    private var retryCount = 0
    
    private let storage = LogStorageManager.shared
    private let repository: LogRepositoryProtocol
    
    #if DEBUG
    private var minimumLogLevel: LogLevel = .verbose
    #else
    private var minimumLogLevel: LogLevel = .info
    #endif
    
    // MARK: - Initialization
    
    init(repository: LogRepositoryProtocol = LogRepository()){
        self.repository = repository
        setupCrashDetection()
        loadPendingLogs()
        observeAppLifecycle()
    }
    
    // MARK: - Setup Crash Detection
    
    private func setupCrashDetection() {
        // Detect previous crash
        if UserDefaults.standard.bool(forKey: "app_crashed") {
            print("🔥 Previous crash detected, sending crash logs immediately")
            sendLogsImmediately(isCrashLog: true)
            UserDefaults.standard.set(false, forKey: "app_crashed")
        }
        
        // Set crash flag (will be cleared on normal app termination)
        UserDefaults.standard.set(true, forKey: "app_crashed")
        
        // Setup exception handler
        NSSetUncaughtExceptionHandler { exception in
            let crashLog = InternalLogEntry(
                type: .serverError, // Changed from .crash
                source: .app,
                level: .critical,
                message: """
                CRASH: \(exception.name.rawValue)
                Reason: \(exception.reason ?? "Unknown")
                Stack: \(exception.callStackSymbols.joined(separator: "\n"))
                """,
                file: "CrashHandler",
                function: "NSSetUncaughtExceptionHandler",
                line: 0,
                userId: UserSession.shared.currentUser?.userId
            )
            
            Logger.shared.logCrash(crashLog)
        }
    }
    
    // MARK: - App Lifecycle Observers
    
    private func observeAppLifecycle() {
        // Send logs when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Clear crash flag on normal termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print("📱 App entering background, sending pending logs")
        sendLogsIfNeeded(force: true)
    }
    
    @objc private func appWillTerminate() {
        print("📱 App terminating normally")
        UserDefaults.standard.set(false, forKey: "app_crashed")
        sendLogsIfNeeded(force: true)
    }
    
    // MARK: - Load Pending Logs
    
    private func loadPendingLogs() {
        queue.async {
            self.pendingLogs = self.storage.loadLogs()
            print("💾 Loaded \(self.pendingLogs.count) pending logs")
            
            // Send if we have enough
            if self.pendingLogs.count >= self.batchSize {
                self.sendLogsIfNeeded(force: false)
            }
        }
    }
    
    // MARK: - Public Logging Methods
    
    func log(
        _ message: String,
        level: LogLevel,
        type: LogType,
        source: LogSource = .app,
        performanceTime: TimeInterval? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Check if we should log this level
        guard level.rawValue >= minimumLogLevel.rawValue else { return }
        
        let entry = InternalLogEntry(
            type: type,
            source: source,
            level: level,
            message: message,
            file: file,
            function: function,
            line: line,
            userId: UserSession.shared.currentUser?.userId,
            performanceTime: performanceTime
        )
        
        // Print to console in debug
        #if DEBUG
        printToConsole(entry)
        #endif
        
        // Add to queue
        queue.async {
            self.pendingLogs.append(entry)
            self.storage.appendLog(entry)
            
            // Check if we should send
            if self.pendingLogs.count >= self.batchSize {
                self.sendLogsIfNeeded(force: false)
            }
            
            // Always send critical logs immediately
            if level.rawValue >= LogLevel.error.rawValue {
                self.sendLogsIfNeeded(force: true)
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Log verbose message - typically for detailed debugging
    func verbose(_ message: String, type: LogType = .apiCall, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .verbose, type: type, file: file, function: function, line: line)
    }
    
    /// Log debug message - for development debugging
    func debug(_ message: String, type: LogType = .apiCall, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, type: type, file: file, function: function, line: line)
    }
    
    /// Log info message - for general information
    func info(_ message: String, type: LogType = .success, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, type: type, file: file, function: function, line: line)
    }
    
    /// Log warning message - for potential issues
    func warning(_ message: String, type: LogType = .badRequest, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, type: type, file: file, function: function, line: line)
    }
    
    /// Log error message - for recoverable errors
    func error(_ message: String, type: LogType = .serverError, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .error, type: type, file: file, function: function, line: line)
    }
    
    /// Log critical message - for severe errors/crashes
    func critical(_ message: String, type: LogType = .serverError, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .critical, type: type, file: file, function: function, line: line)
    }
    
    // MARK: - Specialized Logging Methods
    
    /// Log middleware call - before middleware execution
    func middlewareCall(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, type: .middlewareCall, file: file, function: function, line: line)
    }
    
    /// Log middleware success - after successful middleware execution
    func middlewareSuccess(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, type: .middlewareSuccess, file: file, function: function, line: line)
    }
    
    /// Log API call - for tracking API requests
    func apiCall(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, type: .apiCall, file: file, function: function, line: line)
    }
    
    /// Log bad request - for 4xx client errors
    func badRequest(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .warning, type: .badRequest, file: file, function: function, line: line)
    }
    
    /// Log success - for successful operations
    func success(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, type: .success, file: file, function: function, line: line)
    }
    
    // MARK: - Crash Logging
    
    private func logCrash(_ crashLog: InternalLogEntry) {
        queue.sync {
            pendingLogs.append(crashLog)
            storage.appendLog(crashLog)
            
            // Send immediately
            sendLogsImmediately(isCrashLog: true)
        }
    }
    
    // MARK: - Send Logs
    
    private func sendLogsIfNeeded(force: Bool) {
        queue.async {
            guard !self.isSending else {
                print("⏳ Already sending logs, skipping")
                return
            }
            
            guard force || self.pendingLogs.count >= self.batchSize else {
                print("📊 Only \(self.pendingLogs.count) logs, waiting for \(self.batchSize)")
                return
            }
            
            guard !self.pendingLogs.isEmpty else {
                print("📭 No logs to send")
                return
            }
            
            self.sendBatch()
        }
    }
    
    private func sendLogsImmediately(isCrashLog: Bool) {
        // Synchronous send for crash logs
        let logsToSend = pendingLogs
        guard !logsToSend.isEmpty else { return }
        
        let backendLogs = logsToSend.map { $0.toBackendFormat() }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        repository.sendLogs(backendLogs) { result in
            switch result {
            case .success:
                print("✅ Crash logs sent successfully")
            case .failure(let error):
                print("❌ Failed to send crash logs: \(error)")
            }
            semaphore.signal()
        }
        
        // Wait up to 5 seconds for crash logs to send
        _ = semaphore.wait(timeout: .now() + 5)
    }
    
    private func sendBatch() {
        guard !isSending else { return }
        
        isSending = true
        
        let logsToSend = Array(pendingLogs.prefix(batchSize))
        print("📤 Sending batch of \(logsToSend.count) logs")
        
        let backendLogs = logsToSend.map { $0.toBackendFormat() }
        
        repository.sendLogs(backendLogs) { [weak self] result in
            guard let self = self else { return }
            
            self.queue.async {
                self.isSending = false
                
                switch result {
                case .success(let response):
                    print("✅ Successfully sent \(logsToSend.count) logs: \(response.message)")
                    
                    // Remove sent logs
                    self.pendingLogs.removeFirst(logsToSend.count)
                    self.storage.saveLogs(self.pendingLogs)
                    self.retryCount = 0
                    
                    // Send more if needed
                    if self.pendingLogs.count >= self.batchSize {
                        self.sendLogsIfNeeded(force: false)
                    }
                    
                case .failure(let error):
                    print("❌ Failed to send logs: \(error.localizedDescription)")
                    
                    // Retry logic
                    if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        print("🔄 Retrying... (Attempt \(self.retryCount)/\(self.maxRetries))")
                        
                        DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                            self.sendLogsIfNeeded(force: true)
                        }
                    } else {
                        print("⚠️ Max retries reached, logs will be sent later")
                        self.retryCount = 0
                    }
                }
            }
        }
    }
    
    // MARK: - Performance Tracking
    
    func trackPerformance<T>(
        _ operation: String,
        type: LogType = .apiCall,
        block: () -> T
    ) -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        log(
            operation,
            level: .info,
            type: type,
            performanceTime: timeElapsed
        )
        
        return result
    }
    
    func trackAsyncPerformance<T>(
        _ operation: String,
        type: LogType = .apiCall,
        block: () async -> T
    ) async -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        log(
            operation,
            level: .info,
            type: type,
            performanceTime: timeElapsed
        )
        
        return result
    }
    
    // MARK: - Console Output
    
    private func printToConsole(_ entry: InternalLogEntry) {
        let fileName = (entry.file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: entry.timestamp)
        
        var message = """
        \(entry.level.icon) [\(entry.type.rawValue)] \(entry.message)
        📍 \(fileName):\(entry.line) - \(entry.function)
        ⏰ \(timestamp)
        """
        
        if let perfTime = entry.performanceTime {
            message += "\n⏱️ Performance: \(String(format: "%.3f", perfTime))s"
        }
        
        print(message)
        print(String(repeating: "-", count: 80))
    }
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    // MARK: - Configuration
    
    func setMinimumLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
        info("Minimum log level changed to: \(level)", type: .success)
    }
    
    // MARK: - Manual Controls
    
    func flushLogs() {
        print("🔄 Manually flushing all pending logs")
        sendLogsIfNeeded(force: true)
    }
    
    func clearAllLogs() {
        queue.async {
            self.pendingLogs.removeAll()
            self.storage.clearLogs()
            print("🗑️ All logs cleared")
        }
    }
    
    func getPendingLogCount() -> Int {
        return queue.sync {
            return pendingLogs.count
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

