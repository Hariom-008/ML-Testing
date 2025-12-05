import Foundation

final class LogStorageManager {
    
    static let shared = LogStorageManager()
    
    private let storageKey = "com.byosync.logs.pending"
    private let maxStoredLogs = 500 // Prevent unlimited growth
    private let queue = DispatchQueue(label: "com.byosync.logs.storage", qos: .utility)
    
    private init() {}
    
    // MARK: - Save Logs
    
    func saveLogs(_ logs: [InternalLogEntry]) {
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(logs)
                UserDefaults.standard.set(data, forKey: self.storageKey)
                print("💾 Saved \(logs.count) logs to storage")
            } catch {
                print("❌ Failed to save logs: \(error)")
            }
        }
    }
    
    // MARK: - Load Logs
    
    func loadLogs() -> [InternalLogEntry] {
        return queue.sync {
            guard let data = UserDefaults.standard.data(forKey: storageKey) else {
                return []
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let logs = try decoder.decode([InternalLogEntry].self, from: data)
                print("💾 Loaded \(logs.count) logs from storage")
                return logs
            } catch {
                print("❌ Failed to load logs: \(error)")
                return []
            }
        }
    }
    
    // MARK: - Append Log
    
    func appendLog(_ log: InternalLogEntry) {
        queue.async {
            var logs = self.loadLogsSync()
            logs.append(log)
            
            // Trim if exceeds max
            if logs.count > self.maxStoredLogs {
                logs = Array(logs.suffix(self.maxStoredLogs))
                print("⚠️ Trimmed logs to \(self.maxStoredLogs)")
            }
            
            self.saveLogsSync(logs)
        }
    }
    
    // MARK: - Clear Logs
    
    func clearLogs() {
        queue.async {
            UserDefaults.standard.removeObject(forKey: self.storageKey)
            print("🗑️ Cleared all stored logs")
        }
    }
    
    // MARK: - Get Count
    
    func getLogCount() -> Int {
        return queue.sync {
            return loadLogsSync().count
        }
    }
    
    // MARK: - Private Sync Methods (must be called within queue)
    
    private func loadLogsSync() -> [InternalLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([InternalLogEntry].self, from: data)
        } catch {
            return []
        }
    }
    
    private func saveLogsSync(_ logs: [InternalLogEntry]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(logs)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ Failed to save logs: \(error)")
        }
    }
}
