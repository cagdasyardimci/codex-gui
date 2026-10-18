import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSubagentAvatarTests
{
	@Test func allTwentyEightAvatarsLoadBothAppearanceVariants() throws
	{
		let names = ConversationSubagentAvatars.assetNames
		#expect(names.count == 28)
		#expect(Set(names).count == 28)
		let directory = try #require(ConversationSubagentAvatars.resourceDirectory(in: nil))
		for mode in ["light", "dark"]
		{
			let files = try FileManager.default.contentsOfDirectory(
				at: directory.appendingPathComponent(mode),
				includingPropertiesForKeys: nil
			)
			#expect(Set(files.map
				{
					$0.deletingPathExtension().lastPathComponent
				}) == Set(names))
			for name in names
			{
				let image = try #require(ConversationSubagentAvatars.image(
					named: name,
					dark: mode == "dark"
				))
				#expect(image.isValid)
				#expect(!image.isTemplate)
			}
		}
	}

	@Test func randomAssignmentIsRetainedForEachAgentAcrossRepeatedRendering()
	{
		let names = Set(ConversationSubagentAvatars.assetNames)
		let original = (0 ..< 60).map
		{
			ConversationSubagentAvatars.assetName(for: "avatar-test-agent-\($0)")
		}
		for index in (0 ..< 60).reversed()
		{
			let selected = ConversationSubagentAvatars.assetName(for: "avatar-test-agent-\(index)")
			#expect(names.contains(selected))
			#expect(selected == original[index])
		}
	}

	@Test func appearanceSwitchUsesTheMatchingArtworkWithoutReassigningTheAvatar() throws
	{
		let view = ConversationSubagentAvatarView(
			assetName: "02-gaze-geometric",
			name: "Client"
		)
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 32,
				height: 32
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = view
		defer
		{
			window.contentView = nil
			window.close()
		}
		let frame = view.frame
		var light: NSImage?
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			window.displayIfNeeded()
			let image = try #require(view.image)
			#expect(image === ConversationSubagentAvatars.image(
				named: "02-gaze-geometric",
				dark: name == .darkAqua
			))
			if name == .aqua
			{
				if let light
				{
					#expect(image === light)
				}
				light = image
			}
			else
			{
				#expect(image !== light)
			}
			#expect(view.window === window && view.appearance == nil)
			#expect(view.frame == frame)
			#expect(view.contentTintColor == nil)
			#expect(view.accessibilityLabel() == "Client")
		}
	}

	@Test func packagedAppFindsTheResourceBundleUnderContentsResources() throws
	{
		let temporary = FileManager.default.temporaryDirectory
			.appendingPathComponent("subagent-avatar-bundle-\(UUID().uuidString)")
		let appResources = temporary.appendingPathComponent("CodexGUI.app/Contents/Resources")
		try FileManager.default.createDirectory(
			at: appResources,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: temporary)
		}
		let directory = try #require(ConversationSubagentAvatars.resourceDirectory(in: nil))
		try FileManager.default.copyItem(
			at: directory.deletingLastPathComponent(),
			to: appResources.appendingPathComponent("CodexGUI_CodexGUI.bundle")
		)
		let packaged = try #require(ConversationSubagentAvatars.resourceDirectory(in: appResources))
		#expect(packaged.path.hasPrefix(appResources.path))
		for mode in ["light", "dark"]
		{
			let image = NSImage(contentsOf: packaged.appendingPathComponent(
				"\(mode)/25-gaze-geometric.svg"
			))
			#expect(image?.isValid == true)
		}
	}
}
