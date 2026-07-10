import Foundation

@MainActor
final class ThreadDetailContentLoadController {
    private var generation = 0
    private var task: Task<Bool, Never>?

    func start(_ operation: @escaping @MainActor (Int) async -> Bool) async -> Bool {
        cancel()
        let requestGeneration = generation
        let task = Task { @MainActor in await operation(requestGeneration) }
        self.task = task
        let didComplete = await task.value
        if generation == requestGeneration { self.task = nil }
        return didComplete
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation &+= 1
    }

    func isCurrent(_ requestGeneration: Int) -> Bool {
        !Task.isCancelled && generation == requestGeneration
    }
}
