// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "CodexGUIE2EWorkflow",
	platforms: [.macOS(.v14)],
	products: [
		.executable(
			name: "E2EWorkflow",
			targets: ["E2EWorkflow"]
		),
		.executable(
			name: "E2EEvidence",
			targets: ["E2EEvidence"]
		),
	],
	targets: [
		.executableTarget(
			name: "E2EWorkflow",
			path: "Workflow"
		),
		.executableTarget(
			name: "E2EEvidence",
			path: "Evidence"
		),
	]
)
