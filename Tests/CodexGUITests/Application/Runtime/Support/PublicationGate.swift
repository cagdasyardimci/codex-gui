import Foundation
import Testing

@testable import CodexGUI

@MainActor
final class PublicationGate
{
	private var continuation: CheckedContinuation<Void, Never>?
	var isWaiting: Bool
	{
		continuation != nil
	}

	func wait() async
	{
		await withCheckedContinuation
		{
			continuation = $0
		}
	}

	func release()
	{
		continuation?.resume()
		continuation = nil
	}
}
