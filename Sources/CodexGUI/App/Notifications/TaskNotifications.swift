import AppKit
import UserNotifications

struct TaskNotificationEvent: Equatable, Sendable
{
	let threadID: String
	let title: String
	let body: String
	var owner: WorkspaceLifecycleOwnerReference? = nil
}

/// Filters repeated snapshots so a task transition produces one notification.
struct TaskNotificationTracker
{
	private var previousState: ExecutionState?
	private var previousThreadID: String?

	mutating func observe(_ snapshot: ConversationSnapshot) -> TaskNotificationEvent?
	{
		observe(TaskNotificationPresentation(snapshot: snapshot))
	}

	mutating func observe(_ presentation: TaskNotificationPresentation) -> TaskNotificationEvent?
	{
		let state = presentation.executionState
		let hasJustFinished =
			(state == .completed || state == .failed) && previousState?.isBusy == true
		let terminalOwner = hasJustFinished ? previousThreadID : nil
		let threadID = presentation.activeThreadID ?? terminalOwner
		defer
		{
			previousState = state
			if let activeThreadID = presentation.activeThreadID
			{
				previousThreadID = activeThreadID
			}
		}
		guard let threadID, previousState != nil,
				previousState != state || previousThreadID != threadID
		else
		{
			return nil
		}
		let name =
			presentation.threads.first(where:
				{
					$0.id == threadID
				}).flatMap
			{
				$0.displayTitle
			} ?? "Codex task"
		switch state
		{
		case .awaitingApproval:
			return TaskNotificationEvent(
				threadID: threadID,
				title: "Approval needed",
				body: name
			)
		case .awaitingAnswer:
			return TaskNotificationEvent(
				threadID: threadID,
				title: "Answer needed",
				body: name
			)
		case .completed:
			guard !presentation.taskOutcomeUncertain
			else
			{
				return nil
			}
			return TaskNotificationEvent(
				threadID: threadID,
				title: "Task completed",
				body: name
			)
		case .failed:
			guard !presentation.taskOutcomeUncertain
			else
			{
				return nil
			}
			return TaskNotificationEvent(
				threadID: threadID,
				title: "Task failed",
				body: name
			)
		case .ready, .running, .stopping, .stopped, .disconnected:
			return nil
		}
	}
}

/// Each chat keeps its transition history when one checkout publishes interleaved tasks.
struct TaskNotificationCollection
{
	private struct Scope: Hashable
	{
		let owner: WorkspaceLifecycleOwnerReference?
		let projectPath: String?
		let threadID: String
	}

	private var trackers: [Scope: TaskNotificationTracker] = [:]

	mutating func observe(_ snapshot: ConversationSnapshot) -> TaskNotificationEvent?
	{
		observe(TaskNotificationPresentation(snapshot: snapshot))
	}

	mutating func observe(_ presentation: TaskNotificationPresentation) -> TaskNotificationEvent?
	{
		guard let threadID = presentation.activeThreadID
		else
		{
			return nil
		}
		let scope = Scope(
			owner: presentation.workspaceOwner,
			projectPath: presentation.projectPath,
			threadID: threadID
		)
		var event = trackers[scope, default: TaskNotificationTracker()].observe(presentation)
		event?.owner = presentation.workspaceOwner
		return event
	}
}

@MainActor
final class TaskNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate
{
	var onOpenThread: ((String) -> Void)?
	var onOpenOwnedThread: ((String, WorkspaceLifecycleOwnerReference) -> Void)?
	var onStatusChange: ((String) -> Void)?
	{
		didSet
		{
			onStatusChange?(statusMessage)
		}
	}
	var onAuthorizationChange: ((TaskNotificationAuthorization) -> Void)?
	{
		didSet
		{
			onAuthorizationChange?(authorization)
		}
	}
	private(set) var authorization = TaskNotificationAuthorization.checking
	private(set) var statusMessage = "Checking notification access…"
	private var tracker = TaskNotificationCollection()
	private let center: UNUserNotificationCenter?

	override convenience init()
	{
		self.init(bundle: .main)
	}

	init(bundle: Bundle)
	{
		// The notification API raises an Objective-C exception for an unbundled Swift executable.
		// Check the app identity before calling it; Swift error handling cannot catch that
		// exception.
		if bundle.bundleURL.pathExtension == "app",
			let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
			bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL"
		{
			center = UNUserNotificationCenter.current()
		}
		else
		{
			center = nil
		}
		super.init()
		guard let center
		else
		{
			updateAuthorization(.unavailable)
			updateStatus(
				"Notifications are unavailable for this executable. Run the bundled CodexGUI.app."
			)
			return
		}
		center.delegate = self
		refreshAuthorizationStatus()
	}

	func observe(_ snapshot: ConversationSnapshot)
	{
		observe(TaskNotificationPresentation(snapshot: snapshot))
	}

	func observe(_ presentation: TaskNotificationPresentation)
	{
		// Observe disabled transitions too, so re-enabling alerts does not replay them.
		guard let event = tracker.observe(presentation), center != nil
		else
		{
			return
		}
		let category = TaskNotificationCategory(state: presentation.executionState)
		guard TaskNotificationPreferences().allows(
			category,
			appIsActive: NSApp.isActive
		)
		else
		{
			return
		}
		authorize
		{
			[weak self] in self?.post(
				event,
				category: category
			)
		}
	}

	func requestAuthorization()
	{
		authorize()
	}

	private func authorize(onGranted: (@MainActor @Sendable () -> Void)? = nil)
	{
		guard let center
		else
		{
			updateAuthorization(.unavailable)
			updateStatus(
				"Notifications are unavailable for this executable. Run the bundled CodexGUI.app."
			)
			return
		}
		center.requestAuthorization(options: [.alert, .sound])
		{
			[weak self] granted, error in
			let failure = error?.localizedDescription
			Task
			{
				@MainActor [weak self] in
				guard let self
				else
				{
					return
				}
				if let failure
				{
					self.updateStatus("Notification permission could not be requested: \(failure)")
				}
				else if !granted
				{
					self.updateAuthorization(.denied)
					self.updateStatus(
						"Notifications are disabled. Review this app in macOS System Settings."
					)
				}
				else
				{
					self.refreshAuthorizationStatus()
					onGranted?()
				}
			}
		}
	}

	func refreshAuthorizationStatus()
	{
		guard let center
		else
		{
			return
		}
		center.getNotificationSettings
		{
			[weak self] settings in
			let authorization = settings.authorizationStatus
			Task
			{
				@MainActor [weak self] in
				let message: String
				let state: TaskNotificationAuthorization
				switch authorization
				{
				case .notDetermined:
					state = .notDetermined
					message = "Permission will be requested when a task needs a notification."
				case .denied:
					state = .denied
					message =
						"Notifications are disabled. Review this app in macOS System Settings."
				case .authorized, .provisional, .ephemeral:
					state = .authorized
					message = "Notifications are authorized by macOS."
				@unknown default:
					state = .unavailable
					message = "Notification permission status is unavailable."
				}
				self?.updateAuthorization(state)
				self?.updateStatus(message)
			}
		}
	}

	private func updateAuthorization(_ state: TaskNotificationAuthorization)
	{
		authorization = state
		onAuthorizationChange?(state)
	}

	private func updateStatus(_ message: String)
	{
		statusMessage = message
		onStatusChange?(message)
	}

	private func post(
		_ event: TaskNotificationEvent,
		category: TaskNotificationCategory
	)
	{
		let preferences = TaskNotificationPreferences()
		guard preferences.allows(
			category,
			appIsActive: NSApp.isActive
		), let center
		else
		{
			return
		}
		let content = UNMutableNotificationContent()
		content.title = event.title
		content.body = event.body
		content.userInfo = TaskNotificationPayload.userInfo(event)
		content.userInfo["notificationCategory"] = category.rawValue
		content.sound = TaskNotificationSoundLibrary().notificationSound(
			for: preferences.sound,
			customFilename: preferences.customSoundFilename
		)
		let request = UNNotificationRequest(
			identifier: UUID().uuidString,
			content: content,
			trigger: nil
		)
		center.add(request)
		{
			[weak self] error in
			guard let failure = error?.localizedDescription
			else
			{
				return
			}
			Task
			{
				@MainActor [weak self] in
				self?.updateStatus("Notification could not be delivered: \(failure)")
			}
		}
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	)
	{
		let userInfo = response.notification.request.content.userInfo
		let threadID = userInfo["threadID"] as? String
		let owner = TaskNotificationPayload.owner(userInfo)
		let hasOwner = userInfo["workspaceOwnerKind"] != nil
		completionHandler()
		Task
		{
			@MainActor [weak self] in
			if let threadID
			{
				NSApp.activate(ignoringOtherApps: true)
				if let owner
				{
					self?.onOpenOwnedThread?(threadID, owner)
				}
				else if !hasOwner
				{
					self?.onOpenThread?(threadID)
				}
			}
		}
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
			-> Void
	)
	{
		let category = (notification.request.content.userInfo["notificationCategory"] as? String)
			.flatMap(TaskNotificationCategory.init(rawValue:)) ?? .completion
		let reply = TaskNotificationPresentationReply(completionHandler)
		Task
		{
			@MainActor in
			let preferences = TaskNotificationPreferences()
			guard preferences.allows(
				category,
				appIsActive: NSApp.isActive
			)
			else
			{
				reply.complete([])
				return
			}
			var options: UNNotificationPresentationOptions = [.banner]
			if preferences.soundEnabled
			{
				options.insert(.sound)
			}
			reply.complete(options)
		}
	}
}

/// Notification ownership is captured when posted; a retired session cannot select a new store.
enum TaskNotificationPayload
{
	static func userInfo(_ event: TaskNotificationEvent) -> [AnyHashable: Any]
	{
		var result: [AnyHashable: Any] = ["threadID": event.threadID]
		guard let reference = event.owner
		else
		{
			return result
		}
		result["workspaceSessionID"] = reference.owner.sessionID.uuidString
		if let path = reference.workspace.canonicalCheckoutPath
		{
			result["checkoutPath"] = path
		}
		switch reference.owner
		{
		case .source:
			result["workspaceOwnerKind"] = "source"
		case .managed(
			let workspaceID,
			_
		):
			result["workspaceOwnerKind"] = "managed"
			result["workspaceID"] = workspaceID.uuidString
		}
		return result
	}
	static func owner(_ userInfo: [AnyHashable: Any]) -> WorkspaceLifecycleOwnerReference?
	{
		guard let sessionText = userInfo["workspaceSessionID"] as? String,
				let session = UUID(uuidString: sessionText),
				let kind = userInfo["workspaceOwnerKind"] as? String
		else
		{
			return nil
		}
		let owner: WorkspaceLifecycleOwner
		switch kind
		{
		case "source":
			owner = .source(sessionID: session)
		case "managed":
			guard let workspaceIDText = userInfo["workspaceID"] as? String,
					let workspaceID = UUID(uuidString: workspaceIDText),
					userInfo["checkoutPath"] is String
			else
			{
				return nil
			}
			owner = .managed(
				workspaceID: workspaceID,
				sessionID: session
			)
		default:
			return nil
		}
		return WorkspaceLifecycleOwnerReference(
			owner: owner,
			workspace: WorkspaceIdentity(
				sessionID: session,
				canonicalCheckoutPath: userInfo["checkoutPath"] as? String
			)
		)
	}
}

/// The delegate callback is transferred once to the main actor for foreground preference checks.
private final class TaskNotificationPresentationReply: @unchecked Sendable
{
	private let callback: (UNNotificationPresentationOptions) -> Void

	init(_ callback: @escaping (UNNotificationPresentationOptions) -> Void)
	{
		self.callback = callback
	}

	func complete(_ options: UNNotificationPresentationOptions)
	{
		callback(options)
	}
}
