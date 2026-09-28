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
			],
			sources: [
				"CodexClient/AccountProtocolModels.swift",
				"CodexClient/AppServerError.swift",
				"CodexClient/ConversationProtocolModels.swift",
				"main.swift",
			]
		),
	]
)
