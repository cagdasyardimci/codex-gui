import Foundation

/// Design inputs and simple derived measurements in AppKit points; layout policy is feature-local.
enum LayoutTokens
{
	static let sidebar = Sidebar()
	static let composer = Composer()
	static let permission = Permission()
	static let modelSelector = ModelSelector()
	static let tabContent = TabContent()
	static let window = Window()

	struct Sidebar: Sendable
	{
		static let headingActionSize: CGFloat = 24
		let rowHeight: CGFloat
		let rowSpacing: CGFloat
		let cellInset: CGFloat
		let iconSize: CGFloat
		let iconTextSpacing: CGFloat
		let sectionSpacing: CGFloat
		let sectionContentSpacing: CGFloat

		init(
			rowHeight: CGFloat = 30,
			rowSpacing: CGFloat = 1,
			cellInset: CGFloat = 8,
			iconSize: CGFloat = 16,
			iconTextSpacing: CGFloat = 8,
			sectionSpacing: CGFloat = 16,
			sectionContentSpacing: CGFloat = 4
		)
		{
			self.rowHeight = rowHeight
			self.rowSpacing = rowSpacing
			self.cellInset = cellInset
			self.iconSize = iconSize
			self.iconTextSpacing = iconTextSpacing
			self.sectionSpacing = sectionSpacing
			self.sectionContentSpacing = sectionContentSpacing
		}

		var projectTitleInset: CGFloat
		{
			cellInset + iconSize + iconTextSpacing
		}
		var isValid: Bool
		{
			[rowHeight,
				rowSpacing,
				cellInset,
				iconSize,
				iconTextSpacing,
				sectionSpacing,
				sectionContentSpacing].allSatisfy
			{
				$0.isFinite && $0 >= 0
			}
			&& rowHeight > 0
		}

	}

	struct Composer: Sendable
	{
		let editorHorizontalInset: CGFloat
		let footerHorizontalInset: CGFloat
		let controlHeight: CGFloat
		let minimumHeight: CGFloat
		let availableHeightFraction: CGFloat
		let compactWidthThreshold: CGFloat
		let compactRowSpacing: CGFloat
		let reservedActionSlot: CGFloat
		let actionSpacing: CGFloat

		init(
			editorHorizontalInset: CGFloat = 12,
			footerHorizontalInset: CGFloat = 8,
			controlHeight: CGFloat = 28,
			minimumHeight: CGFloat = 44,
			availableHeightFraction: CGFloat = 0.25,
			compactWidthThreshold: CGFloat = 440,
			compactRowSpacing: CGFloat = 4,
			reservedActionSlot: CGFloat = 0,
			actionSpacing: CGFloat = 8
		)
		{
			self.editorHorizontalInset = editorHorizontalInset
			self.footerHorizontalInset = footerHorizontalInset
			self.controlHeight = controlHeight
			self.minimumHeight = minimumHeight
			self.availableHeightFraction = availableHeightFraction
			self.compactWidthThreshold = compactWidthThreshold
			self.compactRowSpacing = compactRowSpacing
			self.reservedActionSlot = reservedActionSlot
			self.actionSpacing = actionSpacing
		}

		static let topInset: CGFloat = 14
		static let bottomInset: CGFloat = 8
		static let editorFooterSpacing: CGFloat = 4
		static let leadingControlSpacing: CGFloat = 5
		static let leadingPreferenceSpacing: CGFloat = 12
		static let summarySpacing: CGFloat = 8
		static let interactionSpacing: CGFloat = 8
		static let sendIconSize: CGFloat = 16
		static let paneBottomInset: CGFloat = 16

		var stackHorizontalInset: CGFloat
		{
			min(
				editorHorizontalInset,
				footerHorizontalInset
			)
		}
		var nestedFooterWidthAdjustment: CGFloat
		{
			-2 * (footerHorizontalInset - stackHorizontalInset)
		}
		var nestedEditorWidthAdjustment: CGFloat
		{
			-2 * (editorHorizontalInset - stackHorizontalInset)
		}
		var preferenceToActionSpacing: CGFloat
		{
			reservedActionSlot + actionSpacing
		}
		var isValid: Bool
		{
			[editorHorizontalInset,
				footerHorizontalInset,
				compactWidthThreshold,
				compactRowSpacing,
				reservedActionSlot,
				actionSpacing]
				.allSatisfy
				{
					$0.isFinite && $0 >= 0
				}
				&& controlHeight.isFinite && controlHeight > 0
				&& minimumHeight.isFinite && minimumHeight > 0
				&& availableHeightFraction.isFinite
				&& (0 ... 1).contains(availableHeightFraction)
		}

	}

	struct Permission: Sendable
	{
		let leadingInset: CGFloat
		let iconSize: CGFloat
		let iconTextSpacing: CGFloat
		let trailingInset: CGFloat

		init(
			leadingInset: CGFloat = 7,
			iconSize: CGFloat = 16,
			iconTextSpacing: CGFloat = 4,
			trailingInset: CGFloat = 7
		)
		{
			self.leadingInset = leadingInset
			self.iconSize = iconSize
			self.iconTextSpacing = iconTextSpacing
			self.trailingInset = trailingInset
		}

		var titleLeadingInset: CGFloat
		{
			leadingInset + iconSize + iconTextSpacing
		}
		var titleHorizontalInset: CGFloat
		{
			titleLeadingInset + trailingInset
		}
		var isValid: Bool
		{
			[leadingInset, iconSize, iconTextSpacing, trailingInset]
				.allSatisfy
				{
					$0.isFinite && $0 >= 0
				} && iconSize > 0
		}
	}

	struct ModelSelector: Sendable
	{
		let totalHorizontalAllowance: CGFloat
		let maximumWidth: CGFloat
		let boltSize: CGSize
		let boltToTitleSpacing: CGFloat
		let titleToChevronSpacing: CGFloat
		let chevronSize: CGSize

		init(
			totalHorizontalAllowance: CGFloat = 16,
			maximumWidth: CGFloat = 300,
			boltSize: CGSize = CGSize(
				width: 14,
				height: 14
			),
			boltToTitleSpacing: CGFloat = 4,
			titleToChevronSpacing: CGFloat = 4,
			chevronSize: CGSize = CGSize(
				width: 16,
				height: 16
			)
		)
		{
			self.totalHorizontalAllowance = totalHorizontalAllowance
			self.maximumWidth = maximumWidth
			self.boltSize = boltSize
			self.boltToTitleSpacing = boltToTitleSpacing
			self.titleToChevronSpacing = titleToChevronSpacing
			self.chevronSize = chevronSize
		}

		var boltReservedWidth: CGFloat
		{
			boltSize.width + boltToTitleSpacing
		}
		var trailingReservedWidth: CGFloat
		{
			titleToChevronSpacing + chevronSize.width
		}
		var isValid: Bool
		{
			[totalHorizontalAllowance, boltToTitleSpacing, titleToChevronSpacing]
				.allSatisfy
				{
					$0.isFinite && $0 >= 0
				}
				&& [maximumWidth,
					boltSize.width,
					boltSize.height,
					chevronSize.width,
					chevronSize.height].allSatisfy
				{
					$0.isFinite && $0 > 0
				}
		}
	}

	struct TabContent: Sendable
	{
		enum Role: Sendable
		{
			case ordinary, conversation
		}
		let leadingInset: CGFloat
		let trailingInset: CGFloat
		let minimumSelectionWidth: CGFloat
		let minimumWidth: CGFloat
		let maximumWidth: CGFloat
		let closeControlSize: CGFloat
		let moreControlSize: CGFloat

		init(
			leadingInset: CGFloat = 10,
			trailingInset: CGFloat = 7,
			minimumSelectionWidth: CGFloat = 24,
			minimumWidth: CGFloat = 88,
			maximumWidth: CGFloat = 238,
			closeControlSize: CGFloat = 20,
			moreControlSize: CGFloat = 28
		)
		{
			self.leadingInset = leadingInset
			self.trailingInset = trailingInset
			self.minimumSelectionWidth = minimumSelectionWidth
			self.minimumWidth = minimumWidth
			self.maximumWidth = maximumWidth
			self.closeControlSize = closeControlSize
			self.moreControlSize = moreControlSize
		}

		func effectiveMinimum(for role: Role) -> CGFloat
		{
			max(
				minimumWidth,
				leadingInset + minimumSelectionWidth + trailingInset
					+ (role == .ordinary ? closeControlSize : moreControlSize)
			)
		}
		var isValid: Bool
		{
			[leadingInset,
				trailingInset,
				minimumSelectionWidth,
				minimumWidth,
				maximumWidth,
				closeControlSize,
				moreControlSize]
				.allSatisfy
				{
					$0.isFinite && $0 >= 0
				}
				&& effectiveMinimum(for: .ordinary) <= maximumWidth
				&& effectiveMinimum(for: .conversation) <= maximumWidth
				&& minimumSelectionWidth > 0 && closeControlSize > 0 && moreControlSize > 0
		}
	}

	struct Window: Sendable
	{
		let navigationWidth: CGFloat
		let navigationMinimumWidth: CGFloat
		let navigationMaximumWidth: CGFloat
		let reviewWidth: CGFloat
		let reviewMinimumWidth: CGFloat
		let reviewMaximumWidth: CGFloat
		let toolsMinimumWidth: CGFloat
		let conversationMinimumWidth: CGFloat
		let toolsConversationMinimumWidth: CGFloat
		let conversationComfortableWidth: CGFloat
		let filesPreferredWidth: CGFloat
		let filesMaximumWidth: CGFloat

		init(
			navigationWidth: CGFloat = 255,
			navigationMinimumWidth: CGFloat = 200,
			navigationMaximumWidth: CGFloat = 280,
			reviewWidth: CGFloat = 326,
			reviewMinimumWidth: CGFloat = 220,
			reviewMaximumWidth: CGFloat = 360,
			toolsMinimumWidth: CGFloat = 320,
			conversationMinimumWidth: CGFloat = 360,
			toolsConversationMinimumWidth: CGFloat = 320,
			conversationComfortableWidth: CGFloat = 560,
			filesPreferredWidth: CGFloat = 760,
			filesMaximumWidth: CGFloat = 1000
		)
		{
			self.navigationWidth = navigationWidth
			self.navigationMinimumWidth = navigationMinimumWidth
			self.navigationMaximumWidth = navigationMaximumWidth
			self.reviewWidth = reviewWidth
			self.reviewMinimumWidth = reviewMinimumWidth
			self.reviewMaximumWidth = reviewMaximumWidth
			self.toolsMinimumWidth = toolsMinimumWidth
			self.conversationMinimumWidth = conversationMinimumWidth
			self.toolsConversationMinimumWidth = toolsConversationMinimumWidth
			self.conversationComfortableWidth = conversationComfortableWidth
			self.filesPreferredWidth = filesPreferredWidth
			self.filesMaximumWidth = filesMaximumWidth
		}

		func isValid(summaryPreferredWidth: CGFloat) -> Bool
		{
			let values = [navigationWidth,
							navigationMinimumWidth,
							navigationMaximumWidth,
							reviewWidth,
							reviewMinimumWidth,
							reviewMaximumWidth,
							toolsMinimumWidth,
							conversationMinimumWidth,
							toolsConversationMinimumWidth,
							conversationComfortableWidth,
							filesPreferredWidth,
							filesMaximumWidth,
							summaryPreferredWidth]
			guard values.allSatisfy(
				{
					$0.isFinite && $0 > 0
				}
			),
				navigationMinimumWidth <= navigationMaximumWidth,
				reviewMinimumWidth <= reviewMaximumWidth,
				reviewMinimumWidth <= filesMaximumWidth
			else
			{
				return false
			}
			return (navigationMinimumWidth ... navigationMaximumWidth).contains(navigationWidth)
				&& (reviewMinimumWidth ... reviewMaximumWidth).contains(reviewWidth)
				&& (reviewMinimumWidth ... reviewMaximumWidth).contains(summaryPreferredWidth)
				&& (reviewMinimumWidth ... filesMaximumWidth).contains(filesPreferredWidth)
				&& conversationComfortableWidth >= max(
					conversationMinimumWidth,
					toolsConversationMinimumWidth
				)
		}
	}

	enum Tabs
	{
		static let headerHeight: CGFloat = 44
		static let tabHeight: CGFloat = 32
		static var tabWidth: CGFloat
		{
			tabContent.maximumWidth
		}
		static var minimumTabWidth: CGFloat
		{
			tabContent.minimumWidth
		}
		static let tabSpacing: CGFloat = 2
		static let headerLeadingInset: CGFloat = 8
		static let headerTrailingInset: CGFloat = 0
		static let controlSize: CGFloat = 28
		static var closeControlSize: CGFloat
		{
			tabContent.closeControlSize
		}
		static let controlSpacing: CGFloat = 6
		static let separatorWidth: CGFloat = 1
		static let separatorHeight: CGFloat = 16
		static let addButtonSpacing: CGFloat = 8
		static var tabLeadingInset: CGFloat
		{
			tabContent.leadingInset
		}
		static var tabTrailingInset: CGFloat
		{
			tabContent.trailingInset
		}
		static var minimumTabSelectionWidth: CGFloat
		{
			tabContent.minimumSelectionWidth
		}
		static let contentInset: CGFloat = 20
		static let toolsMaximumContentWidth: CGFloat = 768
		static let toolsTwoColumnMinimumWidth: CGFloat = 448
		static let toolColumnSpacing: CGFloat = 16
		static let toolsTopInset: CGFloat = 32
		static let toolsSectionGap: CGFloat = 16
		static let toolTileHeight: CGFloat = 40
		static let toolTileInset: CGFloat = 10
		static let toolTileIconSize: CGFloat = 16
		static let toolTileIconGap: CGFloat = 8
		static let toolShortcutHeight: CGFloat = 16
		static let toolShortcutHorizontalInset: CGFloat = 6
		static let iconSize: CGFloat = 16
		static let paneIconSize = CGSize(
			width: 17.3333,
			height: 16
		)
		static let closeIconSize: CGFloat = 14
	}

	enum Inspector
	{
		static var summaryPaneWidth: CGFloat
		{
			summaryWidth + summaryTrailingInset
		}
		static let boxInset: CGFloat = 12
		static let summaryTrailingInset: CGFloat = 8
		static let contentInset: CGFloat = 16
		static let summaryHorizontalInset: CGFloat = 20
		static let summaryVerticalInset: CGFloat = 10
		static let summaryWidth: CGFloat = 300
		static let initialBoxHeight: CGFloat = 300
		static let detailHeight: CGFloat = 440

	}

	enum Chrome
	{
		static let accountColumnWidth: CGFloat = 52
		static let panelOuterInset: CGFloat = 4
		static let panelTopInset: CGFloat = 2
		static let splitLeadingInset: CGFloat = 1
		static let avatarSize: CGFloat = 32
		static let accountBottomInset: CGFloat = 12

		static var avatarBottomInset: CGFloat
		{
			accountBottomInset
		}

	}

	enum Summary
	{
		static let sectionSpacing: CGFloat = 8
		static let actionSize: CGFloat = 24
		static let headerHeight: CGFloat = 24
		static let contentRowHeight: CGFloat = 28
		static let sourceIconSize: CGFloat = 18
		static let sourceRowSpacing: CGFloat = 12
		static let agentRowSpacing: CGFloat = 4

	}

	enum ProjectActions
	{
		static let actionSize: CGFloat = 20
		static let actionSpacing: CGFloat = 8
		static let actionIconSize: CGFloat = 14
		static var actionWidth: CGFloat
		{
			actionSize * 2 + actionSpacing
		}
	}

	enum TaskActions
	{
		static let actionButtonWidth: CGFloat = 20
		static let actionButtonHeight: CGFloat = 22
		static let actionSpacing: CGFloat = 4
		static let unreadIndicatorSize: CGFloat = 8
		static let progressRingSize: CGFloat = 16

	}

	enum Toolbar
	{
		static let controlSize: CGFloat = 28
		static let rowHeight: CGFloat = 30
		static let controlSpacing: CGFloat = 6
		static let horizontalInset: CGFloat = 8
		static let titleSpacing: CGFloat = 8
		static let maximumTitleWidth: CGFloat = 280

	}

	enum LayoutDefaults
	{
		static let verticalSpacing: CGFloat = 10
		static let horizontalSpacing: CGFloat = 8
		static let contentInset: CGFloat = 16
		static let buttonIconSize: CGFloat = 13
	}

	enum SidebarSelection
	{
		static let newChatTitleHeight: CGFloat = 21
	}

	enum ReadingColumn
	{
		static let maximumWidth: CGFloat = 736
		static let horizontalInset: CGFloat = 40
		static let topInset: CGFloat = 20
		static let bottomInset: CGFloat = 28
		static let centerOffset: CGFloat = 0

	}

	enum Transcript
	{
		static let rowSpacing: CGFloat = 6
		static let replyActionSpacing: CGFloat = 8.5
		static let titleHeight: CGFloat = 16
		static let buttonHeight: CGFloat = 24
		static let codeCopyButtonSize: CGFloat = 36
		static let agentInset = CGSize(
			width: 0,
			height: 4
		)
		static let userInset = CGSize(
			width: 16,
			height: 10
		)
		static let resultInset = CGSize(
			width: 12,
			height: 10
		)
		static let userMinimumWidth: CGFloat = 80
		static let userMaximumWidth: CGFloat = 520
		static let userWidthFraction: CGFloat = 0.7
		static let replyControlSize: CGFloat = 26
		static let replyControlSpacing: CGFloat = 2
		static let replyIconSize: CGFloat = 16
		static let codeCopyControlSize: CGFloat = 32

	}

	enum Markdown
	{
		static let quoteIndent = 16
		static let listIndent = 22
		static let codeInset: CGFloat = 21
		static let codeHeaderHeight: CGFloat = 44
		static let codeBottomPadding: CGFloat = 16
		static let codeBlockSpacing: CGFloat = 17.5
		static let proseLineSpacing: CGFloat = 5.5
		static let listLineSpacing: CGFloat = 3.5
		static let codeLineSpacing: CGFloat = 2
		static let paragraphSpacing: CGFloat = 14.5
		static let listEndSpacing: CGFloat = 10
		static let listParagraphSpacing: CGFloat = 2
		static let followedByListSpacing: CGFloat = 4.5
		static let majorHeadingTopSpacing: CGFloat = 16
		static let headingTopSpacing: CGFloat = 12
		static let headingBottomSpacing: CGFloat = 8
		static let listFirstLineInset: CGFloat = 9
		static let listTextInset: CGFloat = 28
		static let thematicTopSpacing: CGFloat = 8
		static let thematicBottomSpacing: CGFloat = 12
	}

	enum ApprovalPopover
	{
		static let anchorHorizontalOffset: CGFloat = 1
		static let anchorSpacing: CGFloat = 1.7890625
		static let idleIconOpacity: CGFloat = 0.75
		static let hoveredIconOpacity: CGFloat = 1
		static let headerSpacing: CGFloat = 8
		static let width: CGFloat = 439.09375
		static let contentInset: CGFloat = 4
		static let headerHeight: CGFloat = 26
		static let headerTextHeight: CGFloat = 16
		static let horizontalInset: CGFloat = 8
		static let verticalInset: CGFloat = 5
		static let titleHeight: CGFloat = 18.5703125
		static let explanationHeight: CGFloat = 14
		static let iconSlotSize: CGFloat = 16
		static let iconSize: CGFloat = 18
		static let iconTextSpacing: CGFloat = 6
		static let checkSize: CGFloat = 16
		static var rowHeight: CGFloat
		{
			verticalInset * 2 + titleHeight + explanationHeight
		}
		static var preferredHeight: CGFloat
		{
			contentInset * 2 + headerHeight + rowHeight * 3
		}
		static var titleInset: CGFloat
		{
			horizontalInset + iconSlotSize + iconTextSpacing
		}
		static var iconInset: CGFloat
		{
			horizontalInset + (iconSlotSize - iconSize) / 2
		}
	}

	enum TabControls
	{
		static let tabCenterBias: CGFloat = -0.5
		static let separatorVisibilityWidth: CGFloat = 362
	}

	enum NativeChrome
	{
		static let windowButtonOffsetX: CGFloat = 4
		static let windowButtonOffsetY: CGFloat = 2
		static let toolbarTabOffset: CGFloat = 2
		static let toolbarControlOffset: CGFloat = 2
		static let nativeToolbarItemInset: CGFloat = 8
		static var tabBarWidthCompensation: CGFloat
		{
			nativeToolbarItemInset + Chrome.panelOuterInset
		}
	}

	enum ModelPopover
	{
		static let width: CGFloat = 254
		static let fastLeadingInset: CGFloat = 4
		static let fastTopInset: CGFloat = 4
		static let fastSize: CGFloat = 32
		static let resetTrailingInset: CGFloat = 4
		static let resetSize: CGFloat = 32
		static let effortTopInset: CGFloat = 10
		static let effortHeight: CGFloat = 20
		static let modelHeight: CGFloat = 16
		static let modelHorizontalInset: CGFloat = 16
		static let modelChevronSize: CGFloat = 12
		static let actionIconSize: CGFloat = 16
		static let sliderHorizontalInset: CGFloat = 12
		static let sliderTopSpacing: CGFloat = 12
		static let sliderHeight: CGFloat = 28
		static let warningTopSpacing: CGFloat = 6
		static let warningHeight: CGFloat = 26
		static let bottomInset: CGFloat = 10
		static let warningBottomInset: CGFloat = 14
		static let anchorSpacing: CGFloat = 9
		static let shadowOutset: CGFloat = 24
		static var sliderBottom: CGFloat
		{
			effortTopInset + effortHeight + modelHeight + sliderTopSpacing + sliderHeight
		}
	}

	enum TaskHover
	{
		static let width: CGFloat = 320
		static let minimumHeight: CGFloat = 60
		static let contentInset: CGFloat = 10
		static let iconSize: CGFloat = 16
		static let rowSpacing: CGFloat = 8
		static let projectSpacing: CGFloat = 7
	}

	enum ModelList
	{
		static let outerInset: CGFloat = 4
		static let horizontalInset: CGFloat = 8
		static let verticalInset: CGFloat = 5
		static let headerVerticalInset: CGFloat = 4
		static let checkTextSpacing: CGFloat = 6
		static let titleHeight = TypographyTokens.ModelPopover.menuLineHeight
		static let secondaryHeight = TypographyTokens.ModelPopover.modelExplanationLineHeight
		static let checkSize: CGFloat = 16
		static var headerHeight: CGFloat
		{
			titleHeight + 2 * headerVerticalInset
		}
		static var rowHeight: CGFloat
		{
			titleHeight + 2 * verticalInset
		}
	}

	enum EffortSlider
	{
		static let knobDiameter: CGFloat = 28
		static let hoveredKnobDiameter: CGFloat = 32
		static let trackHeight: CGFloat = 24
		static let filledTickDiameter: CGFloat = 3
		static let unfilledTickDiameter: CGFloat = 4
	}
}
