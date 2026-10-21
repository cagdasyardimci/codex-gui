import Foundation

/// Gives WebKit's queued page completion one bounded IPC turn before accepting a deadline failure.
@MainActor
final class MarkdownMermaidPageReadinessProbe
{
	private let maximumWait: Duration
	private let probe: (@escaping @MainActor (Bool) -> Void) -> Void
	private let completion: (Bool) -> Void
	private var timeout: Task<Void, Never>?
	private var started = false
	private var finished = false

	init(
		maximumWait: Duration = .seconds(1),
		probe: @escaping (@escaping @MainActor (Bool) -> Void) -> Void,
		completion: @escaping (Bool) -> Void
	)
	{
		self.maximumWait = maximumWait
		self.probe = probe
		self.completion = completion
	}

	func start()
	{
		guard !started, !finished
		else
		{
			return
		}
		started = true
		timeout = Task
		{
			[weak self, maximumWait] in
			try? await Task.sleep(for: maximumWait)
			guard !Task.isCancelled
			else
			{
				return
			}
			self?.finish(ready: false)
		}
		probe
		{
			[weak self] ready in
			self?.finish(ready: ready)
		}
	}

	func cancel()
	{
		finished = true
		timeout?.cancel()
		timeout = nil
	}

	private func finish(ready: Bool)
	{
		guard !finished
		else
		{
			return
		}
		cancel()
		completion(ready)
	}
}
