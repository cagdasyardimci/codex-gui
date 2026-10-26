import Foundation
import IOKit.pwr_mgt
import IOKit.ps

@MainActor
final class RemoteAccessAwakeService
{
	private var assertion: IOPMAssertionID = 0
	nonisolated(unsafe) private var timer: Timer?
	private var enabled = false

	func update(enabled: Bool)
	{
		self.enabled = enabled
		reconcile()
		if enabled && timer == nil
		{
			timer = Timer.scheduledTimer(
				withTimeInterval: 30,
				repeats: true
			)
			{
				[weak self] _ in
				Task
				{
					@MainActor [weak self] in self?.reconcile()
				}
			}
		}
		else if !enabled
		{
			timer?.invalidate()
			timer = nil
		}
	}

	private func reconcile()
	{
		let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
		let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
		let shouldHold = enabled && source == kIOPSACPowerValue
		if shouldHold && assertion == 0
		{
			IOPMAssertionCreateWithName(
				kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
				IOPMAssertionLevel(kIOPMAssertionLevelOn),
				"Codex GUI remote access" as CFString,
				&assertion
			)
		}
		else if !shouldHold && assertion != 0
		{
			IOPMAssertionRelease(assertion)
			assertion = 0
		}
	}

	deinit
	{
		timer?.invalidate()
		if assertion != 0
		{
			IOPMAssertionRelease(assertion)
		}
	}
}
