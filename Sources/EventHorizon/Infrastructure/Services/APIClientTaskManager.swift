import Foundation

public final class APIClientTaskManager: APIClientTaskManagerProtocol, @unchecked Sendable {

    // MARK: - Properties -
    public static let shared = APIClientTaskManager()
    private var taskStatuses: [String: TaskStatus] = [:]
    private var logger: EHLoggerProtocol?
    private let lock = NSLock()
    private var tasks: [String: any Sendable] = [:]

    // MARK: - Initialization -
    private init() {}

    // MARK: - Configuration
    public func configure(logger: EHLoggerProtocol) {
        self.logger = logger
    }

    // MARK: - Methods -
    public func addTask<T>(
        _ task: Task<T, any Error>,
        for id: String
    ) {
        lock.lock()

        // Prevent adding tasks that are finished or canceled
        if taskStatuses[id] == .finished || taskStatuses[id] == .canceled {
            lock.unlock()
            logger?.log(message: LogMessages.taskAlreadyFinishedOrCanceled(id: id), type: .debug)
            return
        }

        tasks[id] = task
        taskStatuses[id] = .queued

        logger?.log(message: LogMessages.taskAddedAndQueued(id: id), type: .debug)

        lock.unlock()
    }

    public func cancelTask(for id: String) {
        lock.lock()

        if let task = tasks[id] as? Task<Any, any Error>, taskStatuses[id] == .queued || taskStatuses[id] == .inProgress {
            task.cancel()
            tasks.removeValue(forKey: id)
            taskStatuses[id] = .canceled  // Mark the task as canceled
            logger?.log(message: LogMessages.taskCanceled(id: id), type: .debug)
        } else {
            logger?.log(message: LogMessages.noTaskFoundOrInvalidState(id: id, state: String(describing: taskStatuses[id])), type: .error)
        }

        lock.unlock()
    }

    public func setTaskStatus(
        for id: String,
        status: TaskStatus
    ) {
        lock.lock()
        taskStatuses[id] = status
        logger?.log(message: LogMessages.taskStatusUpdated(id: id, status: status), type: .debug)
        lock.unlock()
    }

    public func cancelAllTasks() {
        lock.lock()
        defer { lock.unlock() }
        for id in tasks.keys {
            cancelTask(for: id)
        }
        logger?.log(message: LogMessages.allTasksCanceled, type: .debug)
    }

    public func getTaskStatus(for id: String) -> TaskStatus {
        lock.lock()
        defer { lock.unlock() }
        return taskStatuses[id] ?? .unknown
    }
    
    /// Clean up finished tasks to prevent memory accumulation
    public func cleanupFinishedTasks() {
        lock.lock()
        defer { lock.unlock() }
        
        let finishedTaskIds = taskStatuses.compactMap { key, value in
            value == .finished || value == .canceled ? key : nil
        }
        
        for id in finishedTaskIds {
            tasks.removeValue(forKey: id)
            taskStatuses.removeValue(forKey: id)
        }
        
        logger?.log(message: "Cleaned up \(finishedTaskIds.count) finished tasks", type: .debug)
    }
    
    /// Get current task count for monitoring
    public func getTaskCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return tasks.count
    }
}

private extension APIClientTaskManager {

    // MARK: - Log Messages -
    enum LogMessages {
        static func taskAlreadyFinishedOrCanceled(id: String) -> String {
            "Attempted to add a task for id \(id), but it's already finished or canceled."
        }
        static func taskAddedAndQueued(id: String) -> String {
            "Task for id \(id) added and queued."
        }
        static func taskCanceled(id: String) -> String {
            "Task for id \(id) canceled."
        }
        static func noTaskFoundOrInvalidState(id: String, state: String?) -> String {
            "No task found for id \(id) or task is not in the correct state, state: \(String(describing: state))"
        }
        static func taskStatusUpdated(id: String, status: TaskStatus) -> String {
            "Task for id \(id) status updated to \(status)."
        }
        static let allTasksCanceled = "All tasks have been canceled."
        static func taskInProgress(id: String, inProgress: Bool) -> String {
            "Task for id \(id) is in progress: \(inProgress)."
        }
        static func taskQueued(id: String, queued: Bool) -> String {
            "Task for id \(id) is queued: \(queued)."
        }
        static func taskFinished(id: String, finished: Bool) -> String {
            "Task for id \(id) is finished: \(finished)."
        }
        static func taskCanceledStatus(id: String, canceled: Bool) -> String {
            "Task for id \(id) is canceled: \(canceled)."
        }
    }
}
