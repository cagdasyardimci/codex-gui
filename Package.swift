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
			url: "https://github.com/Pmen225/apps-sdk-ui-swift",
			revision: "07cd708b3670948155d913f863ed4f0d8529ab2e"
		),
	],
	targets: [
		.executableTarget(
			name: "CodexGUI",
			dependencies: [.product(
				name: "OpenAIStyle",
				package: "apps-sdk-ui-swift"
			)],
			resources: [.copy("Resources/AppIcon.icns")]
		),
		.testTarget(
			name: "CodexGUITests",
			dependencies: ["CodexGUI"]
		),
	]
)
