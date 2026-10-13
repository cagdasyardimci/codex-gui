import AppKit
import QuartzCore

@MainActor
final class ModelEffortPopoverView: NSViewController
{
	var onSelectModel: ((String?) -> Void)?
	var onSelectEffort: ((String?) -> Void)?
	var onSetFastMode: ((Bool) -> Void)?
	var onPreferredContentSizeChange: (() -> Void)?

	private var models: [ModelOption] = []
	private var selectedModelID: String?
	private let modelMenuButton = NSButton(
		title: "Default model",
		target: nil,
		action: nil
	)
	private let effortLabel = NSTextField(labelWithString: "Default effort")
	private let fastButton = NSButton(
		title: "Fast mode",
		target: nil,
		action: nil
	)
	private let resetButton = NSButton(
		title: "Reset",
		target: nil,
		action: nil
	)
	private let slider = EffortSlider()
	private let availabilityLabel = NSTextField(wrappingLabelWithString: "")
	private var availabilityHeight: NSLayoutConstraint?
	private var efforts: [String] = []
	private var fastMode = false
	private var effectiveEffort: String?
	private var presented = false

	init()
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		preferredContentSize = NSSize(
			width: 250,
			height: 96
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let surface = EffortPopoverSurface()
		configureEffortLabel()
		configureActionButtons()
		configureModelMenuButton()
		configureSlider()
		configureAvailabilityLabel()
		installControls(in: surface)
		view = surface
		observeVisibilityChanges()
	}

	private func configureEffortLabel()
	{
		effortLabel.font = .systemFont(
			ofSize: 14,
			weight: .medium
		)
		effortLabel.textColor = EffortPopoverStyle.blue
		effortLabel.alignment = .center
		effortLabel.lineBreakMode = .byTruncatingTail
		effortLabel.setAccessibilityLabel("Selected reasoning effort")
	}

	private func configureActionButtons()
	{
		fastButton.target = self
		fastButton.action = #selector(toggleFastMode)
		AppKitControlStyling.styleButton(
			fastButton,
			icon: .bolt
		)
		fastButton.imagePosition = .imageOnly

		resetButton.target = self
		resetButton.action = #selector(resetPreferences)
		AppKitControlStyling.styleButton(
			resetButton,
			icon: .arrowRotateCcw
		)
		resetButton.imagePosition = .imageOnly
		resetButton.contentTintColor = EffortPopoverStyle.icon
		resetButton.toolTip = "Reset effort and fast mode to defaults"
		resetButton.setAccessibilityLabel("Reset effort and fast mode to defaults")
	}

	private func configureModelMenuButton()
	{
		AppKitControlStyling.styleButton(
			modelMenuButton,
			icon: .chevronRight
		)
		modelMenuButton.target = self
		modelMenuButton.action = #selector(showModelMenu)
		modelMenuButton.font = .systemFont(ofSize: 12)
		modelMenuButton.contentTintColor = EffortPopoverStyle.model
		modelMenuButton.image = DesktopIcons.image(
			.chevronRight,
			size: 9
		)
		modelMenuButton.imagePosition = .imageTrailing
		modelMenuButton.lineBreakMode = .byTruncatingMiddle
		modelMenuButton.setAccessibilityLabel("Choose Codex model")
	}

	private func configureSlider()
	{
		slider.cell = EffortSliderCell()
		slider.target = self
		slider.action = #selector(selectSliderEffort)
		slider.isContinuous = true
		slider.allowsTickMarkValuesOnly = true
		slider.focusRingType = .none
		slider.setAccessibilityLabel("Reasoning effort")
		slider.setAccessibilityHelp("Use the arrow keys to choose a supported reasoning effort.")
	}

	private func configureAvailabilityLabel()
	{
		availabilityLabel.font = .systemFont(ofSize: 11)
		availabilityLabel.textColor = .secondaryLabelColor
		availabilityLabel.maximumNumberOfLines = 2
		availabilityLabel.isHidden = true
	}

	private func installControls(in surface: NSView)
	{
		for control in [
			fastButton,
			resetButton,
			effortLabel,
			modelMenuButton,
			slider,
			availabilityLabel,
		]
		{
			control.translatesAutoresizingMaskIntoConstraints = false
			surface.addSubview(control)
		}
		let warningHeight = availabilityLabel.heightAnchor.constraint(equalToConstant: 0)
		availabilityHeight = warningHeight
		NSLayoutConstraint.activate([
			fastButton.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: 10
			),
			fastButton.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: 8
			),
			fastButton.widthAnchor.constraint(equalToConstant: 24),
			fastButton.heightAnchor.constraint(equalToConstant: 24),
			resetButton.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -10
			),
			resetButton.topAnchor.constraint(equalTo: fastButton.topAnchor),
			resetButton.widthAnchor.constraint(equalToConstant: 24),
			resetButton.heightAnchor.constraint(equalToConstant: 24),
			effortLabel.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
			effortLabel.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: 9
			),
			effortLabel.heightAnchor.constraint(equalToConstant: 18),
			effortLabel.leadingAnchor.constraint(greaterThanOrEqualTo: fastButton.trailingAnchor),
			effortLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor),
			modelMenuButton.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
			modelMenuButton.topAnchor.constraint(equalTo: effortLabel.bottomAnchor),
			modelMenuButton.heightAnchor.constraint(equalToConstant: 18),
			modelMenuButton.widthAnchor.constraint(
				lessThanOrEqualTo: surface.widthAnchor,
				constant: -32
			),
			slider.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: 13
			),
			slider.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -13
			),
			slider.topAnchor.constraint(
				equalTo: modelMenuButton.bottomAnchor,
				constant: 14
			),
			slider.heightAnchor.constraint(equalToConstant: 32),
			availabilityLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
			availabilityLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
			availabilityLabel.topAnchor.constraint(
				equalTo: slider.bottomAnchor,
				constant: 6
			),
			warningHeight,
		])
	}

	private func observeVisibilityChanges()
	{
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(visibilityChanged),
			name: NSWindow.didChangeOcclusionStateNotification,
			object: nil
		)
		NSWorkspace.shared.notificationCenter.addObserver(
			self,
			selector: #selector(visibilityChanged),
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		setPresented(true)
	}

	override func viewDidDisappear()
	{
		setPresented(false)
		super.viewDidDisappear()
	}

	func setPresented(_ presented: Bool)
	{
		self.presented = presented
		updateAnimationVisibility()
		if presented
		{
			view.window?.makeFirstResponder(slider.isEnabled ? slider : modelMenuButton)
		}
	}

	func render(
		models: [ModelOption],
		selectedModelID: String?,
		selectedEffort: String?,
		fastMode: Bool
	)
	{
		_ = view
		self.models = models
		self.selectedModelID = selectedModelID
		let selectedModel =
			models.first
				{
					$0.id == selectedModelID
				}
				?? (selectedModelID == nil ? models.first(where: \.isDefault) : nil)
		self.fastMode = fastMode
		effectiveEffort = selectedEffort ?? selectedModel?.defaultReasoningEffort
		efforts = Self.orderedEfforts(for: selectedModel)

		updateModelSelectionTitle()
		updateEffortControls()
		updateAvailabilityWarning()
		slider.ultraSelected = effectiveEffort == "ultra"
		updateFastModeControls()
		updateAnimationVisibility()
		slider.needsDisplay = true
	}

	private static func orderedEfforts(for model: ModelOption?) -> [String]
	{
		var seenEfforts = Set<String>()
		let uniqueEfforts = (model?.supportedReasoningEfforts ?? []).filter
		{
			seenEfforts.insert($0).inserted
		}
		let orderedEfforts = uniqueEfforts.enumerated().sorted
		{
			lhs, rhs in
			let leftOrder = effortOrder(lhs.element)
			let rightOrder = effortOrder(rhs.element)
			return leftOrder == rightOrder ? lhs.offset < rhs.offset : leftOrder < rightOrder
		}
		return orderedEfforts.map(\.element)
	}

	private func updateModelSelectionTitle()
	{
		if let selectedModelID
		{
			let selectedModel = models.first
			{
				$0.id == selectedModelID
			}
			modelMenuButton.title = selectedModel?.displayName ?? "Unavailable: \(selectedModelID)"
		}
		else
		{
			modelMenuButton.title = "Default model"
		}

		modelMenuButton.toolTip = modelMenuButton.title
		modelMenuButton.setAccessibilityValue(modelMenuButton.title)
	}

	private func updateEffortControls()
	{
		effortLabel.stringValue = Self.effortTitle(effectiveEffort)
		effortLabel.textColor = effectiveEffort == "ultra" ? .systemPurple : EffortPopoverStyle.blue
		effortLabel.setAccessibilityValue(effortLabel.stringValue)

		slider.minValue = 0
		slider.maxValue = Double(max(
			1,
			efforts.count - 1
		))
		slider.numberOfTickMarks = efforts.count
		slider.doubleValue = Double(efforts.firstIndex(of: effectiveEffort ?? "") ?? 0)
		slider.isEnabled = !efforts.isEmpty
		slider.setAccessibilityValue(effortLabel.stringValue)
		slider.toolTip = efforts.map
		{
			Self.effortTitle($0)
		}.joined(separator: " · ")
	}

	private func updateAvailabilityWarning()
	{
		let isEffortAvailable = effectiveEffort.map
		{
			efforts.contains($0)
		} ?? false
		if efforts.isEmpty
		{
			availabilityLabel.stringValue = "This model does not list adjustable reasoning efforts."
		}
		else if isEffortAvailable
		{
			availabilityLabel.stringValue = ""
		}
		else
		{
			availabilityLabel.stringValue =
				"Current effort is unavailable. Choose a supported effort or reset."
		}

		let showsWarning = !availabilityLabel.stringValue.isEmpty
		availabilityLabel.isHidden = !showsWarning
		availabilityHeight?.constant = showsWarning ? 26 : 0
		let size = NSSize(
			width: 250,
			height: showsWarning ? 132 : 96
		)
		if preferredContentSize != size
		{
			preferredContentSize = size
			onPreferredContentSizeChange?()
		}
	}

	private func updateFastModeControls()
	{
		slider.fastMode = fastMode
		fastButton.state = fastMode ? .on : .off
		fastButton.image = fastMode
			? DesktopIcons.filledBoltImage(size: 13)
			: DesktopIcons.image(
				.bolt,
				size: 13
			)
		fastButton.contentTintColor = fastMode ? EffortPopoverStyle.blue : EffortPopoverStyle.icon
		fastButton.toolTip = fastMode ? "Disable fast mode" : "Enable fast mode"
		fastButton.setAccessibilityLabel(fastButton.toolTip)
		fastButton.setAccessibilityValue(fastMode ? "On" : "Off")
	}

	static func effortTitle(_ effort: String?) -> String
	{
		guard let effort
		else
		{
			return "Default effort"
		}
		switch effort.lowercased()
		{
		case "low": return "Light"
		case "medium": return "Medium"
		case "high": return "High"
		case "xhigh": return "Extra High"
		case "max": return "Max"
		case "ultra": return "Ultra"
		default: return effort.capitalized
		}
	}

	private static func effortOrder(_ effort: String) -> Int
	{
		["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
			.firstIndex(of: effort) ?? 100
	}

	/// The menu used for presentation; selection is emitted directly as a model ID.
	func makeModelMenu() -> NSMenu
	{
		let menu = NSMenu()
		menu.autoenablesItems = false
		let choices = modelMenuChoices()
		for (index, choice) in choices.enumerated()
		{
			let item = NSMenuItem(
				title: choice.title,
				action: #selector(selectModelItem(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.tag = index
			item.representedObject = choice.id
			item.state = choice.id == selectedModelID ? .on : .off
			menu.addItem(item)
		}
		return menu
	}

	private func modelMenuChoices() -> [(id: String?, title: String)]
	{
		var choices: [(id: String?, title: String)] = [(nil, "Default model")]
		choices.append(contentsOf: models.map
		{
			($0.id, $0.displayName)
		})
		if let selectedModelID, !models.contains(where:
			{
				$0.id == selectedModelID
			})
		{
			choices.append((selectedModelID, "Unavailable: \(selectedModelID)"))
		}
		return choices
	}

	@objc private func showModelMenu()
	{
		makeModelMenu().popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: modelMenuButton.bounds.minY
			),
			in: modelMenuButton
		)
	}

	@objc private func selectModelItem(_ sender: NSMenuItem)
	{
		if sender.tag == 0
		{
			onSelectModel?(nil)
		}
		else if let identifier = sender.representedObject as? String
		{
			onSelectModel?(identifier)
		}
	}

	@objc private func selectSliderEffort()
	{
		guard !efforts.isEmpty
		else
		{
			return
		}
		let index = min(
			efforts.count - 1,
			max(
				0,
				Int(slider.doubleValue.rounded())
			)
		)
		slider.doubleValue = Double(index)
		slider.needsDisplay = true
		let effort = efforts[index]
		guard effort != effectiveEffort
		else
		{
			return
		}
		onSelectEffort?(effort)
	}

	@objc private func toggleFastMode()
	{
		onSetFastMode?(!fastMode)
	}

	@objc private func resetPreferences()
	{
		onSelectEffort?(nil)
		onSetFastMode?(false)
	}

	@objc private func visibilityChanged()
	{
		updateAnimationVisibility()
	}

	private func updateAnimationVisibility()
	{
		slider.isPresented =
			presented && view.window?.isVisible == true
				&& view.window?.occlusionState.contains(.visible) == true
	}
}
