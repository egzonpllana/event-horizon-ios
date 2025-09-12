import Foundation

/// A protocol for managing and tracking the status of tasks in the `APIClient`.
/// This protocol provides methods for adding, canceling, and checking the status of tasks,
/// as well as setting their status within the task manager.
///
/// Conforms to `Sendable` to ensure thread-safety when accessing or modifying tasks in concurrent environments.
public protocol APIClientTaskManagerProtocol: Sendable {

    /// Adds a new task to the manager.
    ///
    /// This method adds a task to the task manager for tracking. The task status is set to `.queued` by default.
    ///
    /// - Parameters:
    ///   - task: The task to be added to the manager.
    ///   - id: A unique identifier for the task.
    ///
    /// - Important: The task will only be added if its status is not `.finished` or `.canceled`.
    func addTask<T>(_ task: Task<T, any Error>, for id: String)

    /// Configures the task manager with a custom logger.
    ///
    /// This method allows setting a logger to be used for logging task lifecycle events such as
    /// adding, canceling, and updating task statuses. It is intended to be called once during
    /// application startup before any task operations are performed.
    ///
    /// - Parameter logger: A custom logger conforming to `EHLoggerProtocol` used for emitting log messages.
    ///
    /// - Important: If not configured, a default logger (`DefaultEHLogger`) will be used.
    /// Calling this method multiple times will override the existing logger.
    func configure(logger: EHLoggerProtocol)

    /// Cancels a task with the given identifier.
    ///
    /// This method cancels the task if it is either `.queued` or `.inProgress`. The task status will be updated to `.canceled` after cancellation.
    ///
    /// - Parameter id: The unique identifier for the task to be canceled.
    func cancelTask(for id: String)

    /// Cancels all tasks that are currently in progress or queued.
    ///
    /// This method will cancel every task in the `tasks` dictionary, and each task's status will be updated to `.canceled`.
    func cancelAllTasks()
    
    /// Returns the current status of a task with the specified identifier.
    ///
    /// This method retrieves the `TaskStatus` for a given task ID. If no status is found, it should return `.unknown`.
    ///
    /// - Parameter id: The unique identifier for the task.
    /// - Returns: The current `TaskStatus` of the task, or `.unknown` if the task does not exist in the manager.
    func getTaskStatus(for id: String) -> TaskStatus
    
    /// Sets the status for a specific task.
    ///
    /// This method allows updating the status of a task, such as marking it as queued, in-progress, finished, or canceled.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for the task.
    ///   - status: The status to set for the task.
    func setTaskStatus(for id: String, status: TaskStatus)
}
