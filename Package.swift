// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "CodexGUI",
	platforms: [.macOS(.v13)],
	products: [.executable(
		name: "CodexGUI",
		targets: ["CodexGUI"]
	)],
	targets: [
		.executableTarget(
			name: "CodexGUI",
			exclude: [
				"Application/Reducers/Composer/ComposerContext.swift",
				"Application/Reducers/Composer/ComposerReducer+Drafts.swift",
				"Application/Reducers/Composer/ComposerReducer+SubmissionLifecycle.swift",
				"Application/Reducers/Composer/ComposerReducer.swift",
				"Application/Reducers/Connection/ConnectionReducer.swift",
				"Application/Reducers/Conversation/ConversationContentReducer.swift",
				"Application/Services/CodexService.swift",
				"CodexClient/AppServer/AppServer+Executable.swift",
				"CodexClient/AppServer/AppServer+Interactions.swift",
				"CodexClient/AppServer/AppServer+Notifications.swift",
				"CodexClient/AppServer/AppServer+Requests.swift",
				"CodexClient/AppServer/AppServer.swift",
				"Features/Conversation/ComposerInputs.swift",
				"Persistence/LocalStorage.swift",
			],
			sources: [
				"App/AppKitLayout.swift",
				"App/BoundedContentScrollView.swift",
				"App/DesktopTheme.swift",
				"CodexClient/AccountProtocolModels.swift",
				"CodexClient/AppServerError.swift",
				"CodexClient/BackendDiagnostics.swift",
				"CodexClient/ConversationProtocolModels.swift",
				"CodexClient/ExecutableVersionProbe.swift",
				"CodexClient/InteractionProtocolModels.swift",
				"CodexClient/JSONLineFramer.swift",
				"CodexClient/ModelProtocolModels.swift",
				"CodexClient/ProtocolModels.swift",
				"CodexClient/SkillProtocolModels.swift",
				"CodexClient/StderrReader.swift",
				"CodexClient/UsageProtocolModels.swift",
				"Features/Conversation/ConversationContent.swift",
				"Persistence/WindowLayoutStore.swift",
				"main.swift",
			]
		),
		.testTarget(
			name: "CodexGUITests",
			dependencies: ["CodexGUI"],
			exclude: [
				"CodexClient/AppServerIntegrationTests.swift",
				"CodexClient/AppServerWorkspaceIsolationTests.swift",
				"CodexClient/BackendTests.swift",
			],
			sources: [
				"CodexClient/ApprovalDecisionTests.swift",
				"CodexClient/BackendDiagnosticsTests.swift",
			]
		),
	]
)
