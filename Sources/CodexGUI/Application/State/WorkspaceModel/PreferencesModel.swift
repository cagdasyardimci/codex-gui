import Foundation

struct PreferencesModel
{
	var pendingPreferenceWrites: [PreferenceWrite.Key: OperationContext] = [:]
	var preferenceWriteErrors: [PreferenceWrite.Key: String] = [:]
	var globalModelPreference: ProjectModelPreference?
	var projectModelPreference: ProjectModelPreference?
	var statusMessage: String?
	var selectedModelID: String?
	var selectedEffort: String?
	var runPreferences = RunPreferences.standard
	var hasStoredModelPreference = false
	var models: [ModelOption] = []
	var modelListError: String?
	var accountDescription = "Checking sign-in…"
	var recentProjects: [URL] = []
	var pinnedProjectPaths: Set<String> = []
	var removedProjectPaths: Set<String> = []
	var pinnedTasks: [ThreadSummary] = []
	var projectDisplayNames: [String: String] = [:]
	var pendingModels: OperationContext?
	var pendingAccount: OperationContext?
	var pendingSignIn: OperationContext?
	var persistenceError: String?
}
