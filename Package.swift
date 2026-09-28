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
				"Persistence/LocalStorage.swift",
			],
			sources: [
				"CodexClient/AccountProtocolModels.swift",
				"CodexClient/AppServerError.swift",
				"CodexClient/ConversationProtocolModels.swift",
				"CodexClient/InteractionProtocolModels.swift",
				"CodexClient/JSONLineFramer.swift",
				"CodexClient/ModelProtocolModels.swift",
				"CodexClient/ProtocolModels.swift",
				"CodexClient/SkillProtocolModels.swift",
				"CodexClient/UsageProtocolModels.swift",
				"main.swift",
			]
		),
	]
)
