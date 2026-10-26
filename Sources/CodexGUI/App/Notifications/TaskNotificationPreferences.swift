import Foundation

enum TaskNotificationCategory: String, Sendable
{
	case completion, permission, question

	init(state: ExecutionState)
	{
		switch state
		{
		case .awaitingApproval: self = .permission
		case .awaitingAnswer: self = .question
		default: self = .completion
		}
	}
}

/// UserDefaults is shared by settings and delivery so pending authorization reads current choices.
// UserDefaults supports concurrent access; this value has no other mutable stored state.
struct TaskNotificationPreferences: @unchecked Sendable
{
	private let defaults: UserDefaults

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	enum CompletionMode: String, CaseIterable
	{
		case always, whenUnfocused, never

		var title: String
		{
			switch self
			{
			case .always: "Always"
			case .whenUnfocused: "Only when unfocused"
			case .never: "Never"
			}
		}
	}

	var completionMode: CompletionMode
	{
		get
		{
			defaults.string(forKey: "taskNotificationCompletionMode")
				.flatMap(CompletionMode.init(rawValue:)) ?? .always
		}
		nonmutating set
		{
			defaults.set(
				newValue.rawValue,
				forKey: "taskNotificationCompletionMode"
			)
		}
	}

	var permissionAlerts: Bool
	{
		get
		{
			defaults
				.object(forKey: "taskNotificationPermissionAlerts") as? Bool ?? true
		}
		nonmutating set
		{
			defaults.set(
				newValue,
				forKey: "taskNotificationPermissionAlerts"
			)
		}
	}

	var questionAlerts: Bool
	{
		get
		{
			defaults.object(forKey: "taskNotificationQuestionAlerts") as? Bool ?? true
		}
		nonmutating set
		{
			defaults.set(
				newValue,
				forKey: "taskNotificationQuestionAlerts"
			)
		}
	}

	var sound: TaskNotificationSound
	{
		get
		{
			if let id = defaults.string(forKey: "taskNotificationSoundID"),
				let selection = TaskNotificationSound(rawValue: id)
			{
				return selection
			}
			let legacy = defaults.object(forKey: "taskNotificationSoundEnabled") as? Bool
			let selection: TaskNotificationSound = legacy == false ? .none : .default
			defaults.set(
				selection.rawValue,
				forKey: "taskNotificationSoundID"
			)
			return selection
		}
		nonmutating set
		{
			defaults.set(
				newValue.rawValue,
				forKey: "taskNotificationSoundID"
			)
			defaults.set(
				newValue != .none,
				forKey: "taskNotificationSoundEnabled"
			)
		}
	}

	var customSoundFilename: String?
	{
		get
		{
			guard let filename = defaults.string(forKey: "taskNotificationCustomSoundFilename"),
					TaskNotificationSoundLibrary.isSafeFilename(filename)
			else
			{
				return nil
			}
			return filename
		}
		nonmutating set
		{
			if let newValue, TaskNotificationSoundLibrary.isSafeFilename(newValue)
			{
				defaults.set(
					newValue,
					forKey: "taskNotificationCustomSoundFilename"
				)
			}
			else
			{
				defaults.removeObject(forKey: "taskNotificationCustomSoundFilename")
			}
		}
	}

	/// Retains compatibility with callers that only need to know whether a sound is selected.
	var soundEnabled: Bool
	{
		get
		{
			sound != .none
		}
		nonmutating set
		{
			sound = newValue ? .default : .none
		}
	}

	func allows(
		_ category: TaskNotificationCategory,
		appIsActive: Bool
	) -> Bool
	{
		switch category
		{
		case .permission: return permissionAlerts
		case .question: return questionAlerts
		case .completion:
			switch completionMode
			{
			case .always: return true
			case .whenUnfocused: return !appIsActive
			case .never: return false
			}
		}
	}
}
