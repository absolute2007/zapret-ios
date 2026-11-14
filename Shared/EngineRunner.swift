import Foundation

/// Runs the embedded byedpi engine on its own thread.
final class EngineRunner {
    /// byedpi keeps global state: one engine per process. In the app the
    /// proxy mode and the strategy tester share this instance.
    static let shared = EngineRunner()

    enum EngineError: LocalizedError {
        case exited(Int32)
        case timeout

        var errorDescription: String? {
            switch self {
            case .exited(let code):
                switch code {
                case -3: return "Движок отклонил параметры стратегии (код -3). Проверьте свои параметры."
                case -5: return "Локальный порт занят другим приложением (код -5)."
                default: return "Движок завершился с кодом \(code)."
                }
            case .timeout: return "Движок не запустился вовремя."
            }
        }
    }

    private let lock = NSLock()
    private var finished: DispatchSemaphore?
    private var exitCode: Int32?
    private(set) var currentArgs: [String] = []

    var isRunning: Bool { zdpi_is_running() != 0 }

    /// Starts the engine and waits until it listens. Throws if it exits early.
    func start(args: [String], timeout: TimeInterval = 4) throws {
        stop()

        let done = DispatchSemaphore(value: 0)
        lock.lock()
        finished = done
        exitCode = nil
        currentArgs = args
        lock.unlock()

        let thread = Thread { [weak self] in
            let cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
            var argv: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
            argv.append(nil)
            let code = zdpi_run(Int32(args.count), &argv)
            cStrings.forEach { free($0) }
            self?.lock.lock()
            self?.exitCode = code
            self?.lock.unlock()
            done.signal()
        }
        thread.name = "zapret.engine"
        thread.stackSize = 1 << 20
        thread.qualityOfService = .userInitiated
        thread.start()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if zdpi_is_running() != 0 { return }
            lock.lock()
            let code = exitCode
            lock.unlock()
            if let code { throw EngineError.exited(code) }
            usleep(30_000)
        }
        throw EngineError.timeout
    }

    /// Stops the engine and waits (bounded) for the thread to finish.
    func stop(timeout: TimeInterval = 3) {
        lock.lock()
        let done = finished
        let alreadyExited = exitCode != nil
        lock.unlock()
        guard let done, !alreadyExited else { return }

        zdpi_stop()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            // Retry the wake-up once; the loop may have been mid-callback.
            zdpi_stop()
            _ = done.wait(timeout: .now() + timeout)
        }
        lock.lock()
        finished = nil
        lock.unlock()
    }
}
