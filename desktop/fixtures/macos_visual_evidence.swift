import AppKit
import ApplicationServices
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

private func emit(_ report: Any) throws
{
	let data = try JSONSerialization.data(withJSONObject: report, options: [.fragmentsAllowed])
	FileHandle.standardOutput.write(data + Data([0x0A]))
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef?
{
	var value: CFTypeRef?
	guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
	else { return nil }
	return value
}

private func focusedField(pid: pid_t) -> [String: Any]?
{
	let application = AXUIElementCreateApplication(pid)
	let system = AXUIElementCreateSystemWide()
	guard let raw = attribute(application, kAXFocusedUIElementAttribute)
		?? attribute(system, kAXFocusedUIElementAttribute),
		CFGetTypeID(raw) == AXUIElementGetTypeID()
	else { return nil }
	let element = raw as! AXUIElement
	var owner: pid_t = 0
	guard AXUIElementGetPid(element, &owner) == .success, owner == pid,
		let rawPosition = attribute(element, kAXPositionAttribute),
		let rawSize = attribute(element, kAXSizeAttribute),
		CFGetTypeID(rawPosition) == AXValueGetTypeID(),
		CFGetTypeID(rawSize) == AXValueGetTypeID()
	else { return nil }
	var position = CGPoint.zero
	var size = CGSize.zero
	guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
		AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
	else { return nil }
	return [
		"pid": pid,
		"role": attribute(element, kAXRoleAttribute) as? String ?? "",
		"description": attribute(element, kAXDescriptionAttribute) as? String ?? "",
		"frame": [[position.x, position.y], [size.width, size.height]],
	]
}

private final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable
{
	private let region: CGRect

	init(region: CGRect)
	{
		self.region = region
	}

	func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType)
	{
		guard type == .screen,
			let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
				as? [[SCStreamFrameInfo: Any]])?.first,
			let status = info[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
			let displayedAt = info[.displayTime] as? UInt64,
			let pixels = sample.imageBuffer,
			CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess
		else { return }
		defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
		guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self)
		else { return }

		let right = min(Int(region.maxX), CVPixelBufferGetWidth(pixels))
		let bottom = min(Int(region.maxY), CVPixelBufferGetHeight(pixels))
		let left = max(Int(region.minX), 0)
		let top = max(Int(region.minY), 0)
		guard left < right, top < bottom else { return }
		let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
		var fingerprint: UInt64 = 0xcbf29ce484222325
		for y in stride(from: top, to: bottom, by: 2)
		{
			for x in stride(from: left, to: right, by: 2)
			{
				let pixel = base + y * rowBytes + x * 4
				for sample in 0..<3
				{
					fingerprint = (fingerprint ^ UInt64(pixel[sample])) &* 0x100000001b3
				}
			}
		}
		try? emit(["displayedAt": displayedAt, "fingerprint": String(fingerprint, radix: 16)])
	}
}

private func number<T: LosslessStringConvertible>(_ text: String, as type: T.Type) throws -> T
{
	guard let value = T(text) else { throw CocoaError(.fileReadCorruptFile) }
	return value
}

private func point(_ values: ArraySlice<String>) throws -> CGPoint
{
	let numbers = try values.map { try number($0, as: Double.self) }
	return CGPoint(x: numbers[0], y: numbers[1])
}

@MainActor
private func record(pid: pid_t, arguments: [String]) async throws
{
	guard arguments.count == 6, CGPreflightScreenCaptureAccess() else { throw CocoaError(.fileReadNoPermission) }
	_ = NSApplication.shared
	let windowID = try number(arguments[0], as: CGWindowID.self)
	let duration = try number(arguments[1], as: Int.self)
	let local = try point(arguments[2...3])
	let size = try point(arguments[4...5])
	let inventory = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
	guard inventory?.contains(where: {
		$0[kCGWindowNumber as String] as? CGWindowID == windowID
			&& $0[kCGWindowOwnerPID as String] as? pid_t == pid
	}) == true else { throw CocoaError(.fileReadNoSuchFile) }
	let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
	guard let window = content.windows.first(where: {
		$0.windowID == windowID && $0.owningApplication?.processID == pid
	}) else { throw CocoaError(.fileReadNoSuchFile) }
	let filter = SCContentFilter(desktopIndependentWindow: window)
	let configuration = SCStreamConfiguration()
	configuration.width = Int(window.frame.width)
	configuration.height = Int(window.frame.height)
	configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
	configuration.pixelFormat = kCVPixelFormatType_32BGRA
	configuration.showsCursor = false
	configuration.ignoreShadowsSingleWindow = true
	let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
	let output = FrameOutput(region: CGRect(x: local.x, y: local.y, width: size.x, height: size.y))
	try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "visual.fixture.frames"))
	try await stream.startCapture()
	try await Task.sleep(for: .milliseconds(duration))
	try await stream.stopCapture()
}

@MainActor
private func sendInput(pid: pid_t, command: String, arguments: [String]) async throws
{
	guard AXIsProcessTrusted(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
	else { throw CocoaError(.fileWriteNoPermission) }
	var timebase = mach_timebase_info_data_t()
	mach_timebase_info(&timebase)

	if command == "key", arguments.isEmpty
	{
		let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
		let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
		down?.flags = []
		up?.flags = []
		let startedAt = mach_absolute_time()
		down?.post(tap: .cghidEventTap)
		up?.post(tap: .cghidEventTap)
		try emit(["startedAt": startedAt, "endedAt": mach_absolute_time(),
			"timebaseNumer": timebase.numer, "timebaseDenom": timebase.denom])
		return
	}

	guard (command == "click" && arguments.count == 2) || (command == "drag" && arguments.count == 4)
	else { throw CocoaError(.fileReadCorruptFile) }
	let start = try point(arguments[0...1])
	let end = command == "drag" ? try point(arguments[2...3]) : start
	func post(_ type: CGEventType, at position: CGPoint)
	{
		CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: .left)?
			.post(tap: .cghidEventTap)
	}
	let startedAt = mach_absolute_time()
	post(.leftMouseDown, at: start)
	if command == "drag"
	{
		for step in 1...40
		{
			let fraction = Double(step) / 40
			post(.leftMouseDragged, at: CGPoint(
				x: start.x + (end.x - start.x) * fraction,
				y: start.y + (end.y - start.y) * fraction
			))
			try await Task.sleep(for: .milliseconds(23))
		}
	}
	post(.leftMouseUp, at: end)
	try emit(["startedAt": startedAt, "endedAt": mach_absolute_time(),
		"timebaseNumer": timebase.numer, "timebaseDenom": timebase.denom])
}

@main
private enum VisualEvidence
{
	static func main() async throws
	{
		let arguments = CommandLine.arguments
		guard arguments.count >= 3, let pid = pid_t(arguments[2]), pid > 0
		else { exit(2) }
		let parameters = Array(arguments.dropFirst(3))
		switch arguments[1]
		{
		case "focus":
			guard parameters.isEmpty, AXIsProcessTrusted() else { exit(2) }
			try emit(focusedField(pid: pid) as Any? ?? NSNull())
		case "frames":
			try await record(pid: pid, arguments: parameters)
		case "key", "click", "drag":
			try await sendInput(pid: pid, command: arguments[1], arguments: parameters)
		default:
			exit(2)
		}
	}
}
