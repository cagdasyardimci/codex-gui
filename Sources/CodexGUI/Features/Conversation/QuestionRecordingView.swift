import AppKit

/// Recording controls and live audio artwork for a question reply.
@MainActor
final class QuestionRecordingView: DesktopSurface
{
	private let waveform = QuestionWaveformView()
	var onCancel: (() -> Void)?
	var onStop: (() -> Void)?
	var onAccept: (() -> Void)?

	init()
	{
		super.init(
			AppKitColorTokens.elevated,
			cornerRadius: 10,
			bordered: true
		)
		let cancel = makeButton(
			symbol: "xmark",
			label: "Cancel dictation",
			primary: false,
			action: #selector(cancelRecording)
		)
		let stop = makeButton(
			symbol: "stop.fill",
			label: "Stop dictation",
			primary: false,
			action: #selector(stopRecording)
		)
		let accept = makeButton(
			symbol: "arrow.up",
			label: "Send dictated answer",
			primary: true,
			action: #selector(acceptRecording)
		)
		let row = AppKitLayout.horizontalStack(
			[cancel, waveform, stop, accept],
			spacing: 8
		)
		row.distribution = .fill
		AppKitLayout.pin(
			row,
			to: self,
			insets: NSEdgeInsets(
				top: 8.5,
				left: 12.5,
				bottom: 8.5,
				right: 12.5
			)
		)
		heightAnchor.constraint(equalToConstant: 45).isActive = true
		waveform.setAccessibilityElement(false)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func append(level: Float)
	{
		waveform.append(level: level)
	}

	func reset()
	{
		waveform.reset()
	}

	private func makeButton(
		symbol: String,
		label: String,
		primary: Bool,
		action: Selector
	) -> DesktopStyledButton
	{
		let presentation: DesktopStyledButton.Presentation = primary ? .recordingSend
			: symbol == "stop.fill" ? .recordingStop : .recordingCancel
		let button = DesktopStyledButton(
			title: "",
			presentation: presentation,
			target: self,
			action: action
		)
		button.image = NSImage(
			systemSymbolName: symbol,
			accessibilityDescription: nil
		)
		button.imagePosition = .imageOnly
		button.setAccessibilityLabel(label)
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: 28),
			button.heightAnchor.constraint(equalToConstant: 28),
		])
		return button
	}

	@objc private func cancelRecording()
	{
		onCancel?()
	}
	@objc private func stopRecording()
	{
		onStop?()
	}
	@objc private func acceptRecording()
	{
		onAccept?()
	}
}

/// Audio sample artwork uses a fixed bar rhythm while adapting to the available reply width.
@MainActor
private final class QuestionWaveformView: NSView
{
	private var samples: [CGFloat] = []
	private var targetLevel: CGFloat = 0
	private var smoothedLevel: CGFloat = 0
	private var timer: Timer?
	private var scrollOffset: CGFloat = 0

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		timer?.invalidate()
		timer = nil
		guard window != nil
		else
		{
			return
		}
		let timer = Timer(
			timeInterval: 1.0 / 30.0,
			repeats: true
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				self?.advanceFrame()
			}
		}
		RunLoop.main.add(
			timer,
			forMode: .common
		)
		self.timer = timer
	}

	private func advanceFrame()
	{
		guard !isHiddenOrHasHiddenAncestor
		else
		{
			return
		}
		smoothedLevel += (targetLevel - smoothedLevel) * 0.35
		scrollOffset += 0.65
		if scrollOffset >= 5
		{
			scrollOffset -= 5
			samples.append(smoothedLevel)
			if samples.count > 640
			{
				samples.removeFirst(samples.count - 640)
			}
		}
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: 160,
			height: 28
		)
	}

	func append(level: Float)
	{
		targetLevel = CGFloat(min(
			max(
				level,
				0
			),
			1
		))
	}

	func reset()
	{
		samples.removeAll()
		targetLevel = 0
		smoothedLevel = 0
		scrollOffset = 0
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let drawingBounds = bounds.insetBy(
			dx: min(
				20,
				bounds.width / 4
			),
			dy: 0
		)
		let count = max(
			1,
			Int(drawingBounds.width / 5) + 2
		)
		let visible = Array(samples.suffix(count))
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: drawingBounds).addClip()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		let bars = NSBezierPath()
		for index in 0 ..< count
		{
			let sampleIndex = index - (count - visible.count)
			let level = sampleIndex >= 0 ? visible[sampleIndex] : 0
			let height = max(
				2,
				level * (bounds.height - 4)
			)
			let bar = NSRect(
				x: drawingBounds.minX + CGFloat(index) * 5 - scrollOffset,
				y: bounds.midY - height / 2,
				width: 2,
				height: height
			)
			bars.append(NSBezierPath(
				roundedRect: bar,
				xRadius: 1,
				yRadius: 1
			))
		}
		bars.addClip()
		let color = AppKitColorTokens.recordingWaveform
		NSGradient(
			colors: [.clear, color, color, .clear],
			atLocations: [0, 0.04, 0.96, 1],
			colorSpace: .deviceRGB
		)?.draw(
			in: drawingBounds,
			angle: 0
		)
	}
}
