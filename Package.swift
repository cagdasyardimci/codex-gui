// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "CodexGUI",
	platforms: [.macOS(.v14)],
	products: [.executable(
		name: "CodexGUI",
		targets: ["CodexGUI"]
	)],
	dependencies: [
		.package(
			url: "https://github.com/swiftlang/swift-markdown",
			exact: "0.9.0"
		),
		.package(
			url: "https://github.com/smittytone/HighlighterSwift",
			exact: "3.1.0"
		),
		.package(
			url: "https://github.com/mgriebling/SwiftMath",
			exact: "1.7.3"
		),
		.package(
			url: "https://github.com/Pmen225/apps-sdk-ui-swift",
			revision: "07cd708b3670948155d913f863ed4f0d8529ab2e"
		),
	],
	targets: [
		.executableTarget(
			name: "CodexGUI",
			dependencies: [
				.product(
					name: "OpenAIStyle",
					package: "apps-sdk-ui-swift"
				),
				.product(
					name: "Markdown",
					package: "swift-markdown"
				),
				.product(
					name: "Highlighter",
					package: "HighlighterSwift"
				),
				.product(
					name: "SwiftMath",
					package: "SwiftMath"
				),
			],
			resources: [
				.copy("Resources/AppIcon.icns"),
				.copy("Resources/RemoteAccess"),
				.copy("Resources/Mermaid"),
				.copy("Resources/SubagentAvatars")
			]
		),
		.testTarget(
			name: "CodexGUITests",
			dependencies: ["CodexGUI"]
		),
	]
)
