import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct UITestUIEvidenceTests
{
	@Test func optInCapturesRetainedViewerAndRefreshesAtomicCompanion() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let directory = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			defer
			{
				try? FileManager.default.removeItem(at: directory)
			}
			let disabled = UITestEvidenceRecorder(path: "relative.json")
			#expect(!disabled.isEnabled)
			let disabledEvidence = UITestUIEvidence(recorder: disabled)
			disabledEvidence.capture()
			await disabled.flush()
			#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

			let path = directory.appendingPathComponent("state.json")
			let recorder = UITestEvidenceRecorder(path: path.path)
			let evidence = UITestUIEvidence(recorder: recorder)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 600,
					height: 500
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.orderFront(nil)
			let label = NSTextField(labelWithString: "private fixture")
			label.font = NSFont.systemFont(ofSize: 24)
			window.contentView?.addSubview(label)
			defer
			{
				window.close()
			}
			let viewer = ExpandedImageViewController(name: "private fixture")
			window.contentView?.addSubview(viewer.view)
			viewer.view.frame = window.contentView?.bounds ?? .zero
			viewer.view.layoutSubtreeIfNeeded()
			viewer.configureDiagram(
				NSImage(size: NSSize(
					width: 300,
					height: 600
				)),
				appearance: .init(named: .aqua)!
			)
			viewer.setZoom(1.5)
			evidence.viewerChanged(viewer)
			evidence.capture()
			await recorder.flush()
			let companion = directory.appendingPathComponent("state.json.ui.json")
			let firstData = try Data(contentsOf: companion)
			let first = try #require(JSONSerialization
				.jsonObject(with: firstData) as? [String: Any])
			let viewers = try #require(first["expandedViewers"] as? [[String: Any]])
			#expect(viewers.count == 1)
			#expect((viewers.first?["zoom"] as? Double) == 1.5)
			let windows = try #require(first["windows"] as? [[String: Any]])
			let capturedWindow = try #require(windows
				.first
				{
					($0["number"] as? Int) == window.windowNumber
				})
			let views = try #require(capturedWindow["views"] as? [[String: Any]])
			#expect(views.contains
			{
				(($0["font"] as? [String: Any])?["size"] as? Double) == 24
			})
			#expect(!(String(
				decoding: firstData,
				as: UTF8.self
			).contains("private fixture")))
			viewer.setZoom(2)
			window.appearance = NSAppearance(named: .darkAqua)
			evidence.capture()
			await recorder.flush()
			let second = try #require(JSONSerialization
				.jsonObject(with: Data(contentsOf: companion)) as? [String: Any])
			let secondViewers = try #require(second["expandedViewers"] as? [[String: Any]])
			#expect((secondViewers.first?["zoom"] as? Double) == 2)
			#expect((second["sequence"] as? Int ?? 0) > (first["sequence"] as? Int ?? 0))
			let changedWindows = try #require(second["windows"] as? [[String: Any]])
			let changedWindow = try #require(changedWindows
				.first
				{
					($0["number"] as? Int) == window.windowNumber
				})
			#expect((changedWindow["appearance"] as? String) == NSAppearance.Name.darkAqua.rawValue)
			evidence.viewerChanged(
				viewer,
				active: false
			)
			evidence.capture()
			await recorder.flush()
			let last = try #require(JSONSerialization
				.jsonObject(with: Data(contentsOf: companion)) as? [String: Any])
			#expect((last["expandedViewers"] as? [[String: Any]])?.isEmpty == true)
			#expect(!FileManager.default.fileExists(atPath: path.path))
		}
	}
}
