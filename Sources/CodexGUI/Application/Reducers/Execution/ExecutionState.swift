import Foundation

enum ExecutionState: String, Equatable
{
	case ready
	case running
	case awaitingApproval
	case awaitingAnswer
	case stopping
	case stopped
	case completed
	case failed
	case disconnected

	var title: String
	{
		switch self
		{
		case .ready: "Ready"
		case .running: "Running"
		case .awaitingApproval: "Awaiting approval"
		case .awaitingAnswer: "Awaiting answer"
		case .stopping: "Stopping"
		case .stopped: "Stopped"
		case .completed: "Completed"
		case .failed: "Failed"
		case .disconnected: "Disconnected"
		}
	}

	var isBusy: Bool
	{
		switch self
		{
		case .running, .awaitingApproval, .awaitingAnswer, .stopping: true
		case .ready, .stopped, .completed, .failed, .disconnected: false
		}
	}
}
