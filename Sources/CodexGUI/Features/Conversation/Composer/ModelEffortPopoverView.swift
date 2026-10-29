import AppKit
import QuartzCore

@MainActor
final class ModelEffortPopoverView: NSViewController, DesktopPopoverMaterialContent
{
	var onSelectModel: ((String?) -> Void)?
	var onSelectEffort: ((String?) -> Void)?
	var onSetFastMode: ((Bool) -> Void)?
	var onPreferredContentSizeChange: (() -> Void)?
	var onModelListPresentationChange: (() -> Void)?
	private(set) var isShowingModelList = false

	private var models: [ModelOption] = []
	private var selectedModelID: String?
	private let modelMenuButton = DesktopStyledButton(
		title: "Default model",
		presentation: .menuTrigger
	)
	private let effortLabel = NSTextField(labelWithString: "Default effort")
	private let fastButton = DesktopStyledButton(
		title: "Fast mode",
		presentation: .toggle,
		size: .regular
	)
	private let resetButton = DesktopStyledButton(
		title: "Reset",
		presentation: .icon,
		size: .regular
	)
	private let slider = EffortSlider()
	private var efforts: [String] = []
	private var fastMode = false
	private var effectiveEffort: String?
	private var presented = false
	let modelList = ModelPickerListView()

	init()
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		preferredContentSize = NSSize(
			width: LayoutTokens.ModelPopover.width,
			height: Self.preferredHeight()
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let surface = NSView()
		configureEffortLabel()
		configureActionButtons()
		configureModelMenuButton()
		configureSlider()
		installControls(in: surface)
		AppKitLayout.pin(
			modelList,
			to: surface,
			inset: 0
		)
		modelList.isHidden = true
		modelList.onSelect =
		{
			[weak self] modelID in
			self?.onSelectModel?(modelID)
			self?.setModelListVisible(false)
		}
		view = surface
		observeVisibilityChanges()
	}

	private func configureEffortLabel()
	{
		effortLabel.font = AppKitFontResolver.font(TypographyTokens.ModelPopover.effort)
		effortLabel.textColor = EffortPopoverStyle.blue
		effortLabel.alignment = .center
		effortLabel.lineBreakMode = .byTruncatingTail
		effortLabel.setAccessibilityLabel("Selected reasoning effort")
	}

	private func configureActionButtons()
	{
		fastButton.target = self
		fastButton.action = #selector(toggleFastMode)
		fastButton.image = DesktopIcons.image(.bolt)

		resetButton.target = self
		resetButton.action = #selector(resetPreferences)
		resetButton.image = DesktopIcons.image(.arrowRotateCcw)
		resetButton.toolTip = "Reset to default"
		resetButton.setAccessibilityLabel("Reset effort and fast mode to defaults")
	}

	private func configureModelMenuButton()
	{
		modelMenuButton.target = self
		modelMenuButton.action = #selector(showModelMenu)
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

	private func installControls(in surface: NSView)
	{
		for control in [
			fastButton,
			resetButton,
			effortLabel,
			modelMenuButton,
			slider,
		]
		{
			control.translatesAutoresizingMaskIntoConstraints = false
			surface.addSubview(control)
		}
		NSLayoutConstraint.activate([
			fastButton.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: LayoutTokens.ModelPopover.fastLeadingInset
			),
			fastButton.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: LayoutTokens.ModelPopover.fastTopInset
			),
			resetButton.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -LayoutTokens.ModelPopover.resetTrailingInset
			),
			resetButton.topAnchor.constraint(equalTo: fastButton.topAnchor),
			effortLabel.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
			effortLabel.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: LayoutTokens.ModelPopover.effortTopInset
			),
			effortLabel.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ModelPopover.effortHeight),
			effortLabel.leadingAnchor.constraint(greaterThanOrEqualTo: fastButton.trailingAnchor),
			effortLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor),
			modelMenuButton.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
			modelMenuButton.topAnchor.constraint(equalTo: effortLabel.bottomAnchor),
			modelMenuButton.widthAnchor.constraint(
				lessThanOrEqualTo: surface.widthAnchor,
				constant: -2 * LayoutTokens.ModelPopover.modelHorizontalInset
			),
			slider.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: LayoutTokens.ModelPopover.sliderHorizontalInset
			),
			slider.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -LayoutTokens.ModelPopover.sliderHorizontalInset
			),
			slider.topAnchor.constraint(
				equalTo: modelMenuButton.bottomAnchor,
				constant: LayoutTokens.ModelPopover.sliderTopSpacing
			),
			slider.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ModelPopover.sliderHeight),
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
		if !presented, isShowingModelList
		{
			setModelListVisible(false)
		}
		updateAnimationVisibility()
		if presented
		{
			let selectedModel = models.first
			{
				$0.id == selectedModelID
			}
			?? (selectedModelID == nil ? models.first(where: \.isDefault) : nil)
			efforts = ReasoningEffortVisibility().visibleEfforts(
				advertised: Self.orderedEfforts(for: selectedModel),
				retaining: effectiveEffort
			)
			updateEffortControls()
			updatePreferredContentSize()
			if isShowingModelList
			{
				modelList.focusSelectedRow()
			}
			else
			{
				view.window?.makeFirstResponder(slider.isEnabled ? slider : modelMenuButton)
			}
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
		efforts = ReasoningEffortVisibility().visibleEfforts(
			advertised: Self.orderedEfforts(for: selectedModel),
			retaining: effectiveEffort
		)

		updateModelSelectionTitle()
		updateEffortControls()
		updatePreferredContentSize()
		slider.ultraSelected = effectiveEffort == "ultra"
		updateFastModeControls()
		updateAnimationVisibility()
		if isShowingModelList
		{
			renderModelList()
			updatePreferredContentSize()
		}
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
			modelMenuButton.title = selectedModel?.displayName ?? selectedModelID
		}
		else
		{
			modelMenuButton.title = "Default model"
		}

		modelMenuButton.toolTip = nil
		modelMenuButton.setAccessibilityValue(modelMenuButton.title)
	}

	private func updateEffortControls()
	{
		effortLabel.stringValue = ModelPreferencePresentation.effortTitle(effectiveEffort)
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
	}

	private func updatePreferredContentSize()
	{
		let size = NSSize(
			width: LayoutTokens.ModelPopover.width,
			height: isShowingModelList ? modelList.preferredHeight
				: Self.preferredHeight()
		)
		if preferredContentSize != size
		{
			preferredContentSize = size
			onPreferredContentSizeChange?()
		}
	}

	private nonisolated static func preferredHeight() -> CGFloat
	{
		let sliderBottom = LayoutTokens.ModelPopover.effortTopInset
			+ LayoutTokens.ModelPopover.effortHeight + LayoutTokens.Button.compactHeight
			+ LayoutTokens.ModelPopover.sliderTopSpacing + LayoutTokens.ModelPopover.sliderHeight
		return sliderBottom + LayoutTokens.ModelPopover.bottomInset
	}

	private func updateFastModeControls()
	{
		slider.fastMode = fastMode
		fastButton.state = fastMode ? .on : .off
		fastButton.image = fastMode
			? DesktopIcons.filledBoltImage()
			: DesktopIcons.image(.bolt)
		fastButton.toolTip = "1.5x speed\nMore usage"
		fastButton.setAccessibilityLabel(fastMode ? "Disable fast mode" : "Enable fast mode")
		fastButton.setAccessibilityValue(fastMode ? "On" : "Off")
	}

	private static func effortOrder(_ effort: String) -> Int
	{
		["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
			.firstIndex(of: effort) ?? 100
	}

	private func modelMenuChoices() -> [ModelPickerChoice]
	{
		var choices = [ModelPickerChoice(
			id: nil,
			title: "Default"
		)]
		choices.append(contentsOf: models.map
		{
			ModelPickerChoice(
				id: $0.id,
				title: $0.displayName
			)
		})
		if let selectedModelID, !models.contains(where:
			{
				$0.id == selectedModelID
			})
		{
			choices.append(ModelPickerChoice(
				id: selectedModelID,
				title: selectedModelID
			))
		}
		return choices
	}

	@objc private func showModelMenu()
	{
		showModelList()
	}

	func showModelList()
	{
		_ = view
		renderModelList()
		setModelListVisible(true)
	}

	private func renderModelList()
	{
		modelList.render(
			choices: modelMenuChoices(),
			selectedID: selectedModelID
		)
	}

	private func setModelListVisible(_ visible: Bool)
	{
		isShowingModelList = visible
		modelList.isHidden = !visible
		for control in [fastButton, resetButton, effortLabel, modelMenuButton, slider]
		{
			control.isHidden = visible
		}
		updatePreferredContentSize()
		updateAnimationVisibility()
		onModelListPresentationChange?()
		if presented
		{
			if visible
			{
				modelList.focusSelectedRow()
			}
			else
			{
				view.window?.makeFirstResponder(slider.isEnabled ? slider : modelMenuButton)
			}
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
			presented && !isShowingModelList && view.window?.isVisible == true
				&& view.window?.occlusionState.contains(.visible) == true
	}
}
