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
				"Application/Services/CodexService.swift",
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
				"main.swift",
			]
		),
	]
)
