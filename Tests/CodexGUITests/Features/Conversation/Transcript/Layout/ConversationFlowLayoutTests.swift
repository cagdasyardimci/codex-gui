import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationFlowLayoutTests
{
	@Test func readingColumnKeepsMinimumInsetAndExpandsOnWidePanes() throws
	{
		_ = NSApplication.shared
		for (paneWidth, contentWidth, inset): (CGFloat, CGFloat, CGFloat) in [
			(950, 736, 107),
			(600, 520, 40),
		]
		{
			let source = LayoutSource(heights: [40])
			let fixture = makeLayout(
				source: source,
				width: paneWidth
			)
			defer
			{
				fixture.collection.dataSource = nil
				fixture.collection.delegate = nil
			}
			let attributes = try #require(fixture.layout.layoutAttributesForItem(
				at: IndexPath(
					item: 0,
					section: 0
				)
			))
			#expect(attributes.frame.width == contentWidth)
			#expect(attributes.frame.minX == inset)
			#expect(paneWidth - attributes.frame.maxX == inset)
		}
	}

	@Test func visibleAttributesMatchEveryIntersectingRowAcrossADeepTranscript() throws
	{
		_ = NSApplication.shared
		let source = LayoutSource(heights: (0 ..< 2_000).map
		{
			CGFloat(24 + ($0 % 9) * 13)
		})
		let fixture = makeLayout(source: source)
		defer
		{
			fixture.collection.dataSource = nil
			fixture.collection.delegate = nil
		}
		fixture.layout.verticalGap =
		{
			$0 % 7 == 0 ? 18 : 0
		}
		fixture.layout.invalidateContentAttributes()
		fixture.layout.prepare()
		try assertVisibleAttributes(
			fixture,
			heights: source.heights
		)
		let previousBottom = fixture.layout.collectionViewContentSize.height
		source.heights[960] += 800
		fixture.layout.invalidateContentMetrics()
		fixture.layout.prepare()
		#expect(fixture.layout.collectionViewContentSize.height > previousBottom)
		try assertVisibleAttributes(
			fixture,
			heights: source.heights
		)
	}

	@Test func visibleAttributesIncludeTallRowsOverlappingShorterRows() throws
	{
		_ = NSApplication.shared
		let source = LayoutSource(heights: [400, 30, 50, 20, 140, 80])
		let fixture = makeLayout(source: source)
		defer
		{
			fixture.collection.dataSource = nil
			fixture.collection.delegate = nil
		}
		fixture.layout.verticalGap =
		{
			$0 == 1 ? -390 : ($0 == 4 ? -100 : 0)
		}
		fixture.layout.invalidateContentAttributes()
		fixture.layout.prepare()
		try assertVisibleAttributes(
			fixture,
			heights: source.heights
		)
		let visible = fixture.layout.layoutAttributesForElements(in: NSRect(
			x: 0,
			y: 200,
			width: 450,
			height: 20
		))
		#expect(visible.contains
		{
			$0.indexPath?.item == 0
		})
	}

	private func assertVisibleAttributes(
		_ fixture: LayoutFixture,
		heights: [CGFloat]
	) throws
	{
		let attributes = try heights.indices.map
		{
			try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(
				item: $0,
				section: 0
			)))
		}
		let rectangles = attributes.enumerated().flatMap
		{
			index, attributes in
			[
				NSRect(
					x: 0,
					y: attributes.frame.minY - 1,
					width: 450,
					height: 1
				),
				NSRect(
					x: 0,
					y: attributes.frame.maxY,
					width: 450,
					height: 1
				),
				NSRect(
					x: 0,
					y: attributes.frame.minY + 1,
					width: 450,
					height: 150
				),
				NSRect(
					x: 451,
					y: attributes.frame.minY,
					width: 30,
					height: 150
				),
				NSRect(
					x: 0,
					y: attributes.frame.minY,
					width: 450,
					height: 0
				),
				NSRect(
					x: 0,
					y: attributes.frame.maxY,
					width: 450,
					height: 0
				),
				NSRect(
					x: 0,
					y: CGFloat(index * 41),
					width: 450,
					height: 0
				),
			]
		}
		for rectangle in rectangles
		{
			let expectedAttributes = attributes.filter
			{
				$0.frame.intersects(rectangle)
			}
			let expected = Set(expectedAttributes.compactMap(\.indexPath))
			let actual = Set(fixture.layout.layoutAttributesForElements(in: rectangle)
				.compactMap(\.indexPath))
			#expect(
				actual == expected,
				"Rect: \(rectangle); expected frames: \(expectedAttributes.map(\.frame))"
			)
		}
	}

	private struct LayoutFixture
	{
		let collection: NSCollectionView
		let scroll: NSScrollView
		let layout: ConversationFlowLayout
	}

	private func makeLayout(
		source: LayoutSource,
		width: CGFloat = 450
	) -> LayoutFixture
	{
		let collection = NSCollectionView(frame: NSRect(
			x: 0,
			y: 0,
			width: width,
			height: 600
		))
		let scroll = NSScrollView(frame: collection.frame)
		scroll.documentView = collection
		let layout = ConversationFlowLayout()
		layout.minimumLineSpacing = 18
		collection.collectionViewLayout = layout
		collection.register(
			NSCollectionViewItem.self,
			forItemWithIdentifier: NSUserInterfaceItemIdentifier("layoutItem")
		)
		collection.dataSource = source
		collection.delegate = source
		collection.reloadData()
		collection.layoutSubtreeIfNeeded()
		layout.prepare()
		return LayoutFixture(
			collection: collection,
			scroll: scroll,
			layout: layout
		)
	}

	private final class LayoutSource: NSObject,
		NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout
	{
		var heights: [CGFloat]
		init(heights: [CGFloat])
		{
			self.heights = heights
		}

		func collectionView(
			_ collectionView: NSCollectionView,
			numberOfItemsInSection section: Int
		) -> Int
		{
			heights.count
		}

		func collectionView(
			_ collectionView: NSCollectionView,
			itemForRepresentedObjectAt indexPath: IndexPath
		) -> NSCollectionViewItem
		{
			collectionView.makeItem(
				withIdentifier: NSUserInterfaceItemIdentifier("layoutItem"),
				for: indexPath
			)
		}

		func collectionView(
			_ collectionView: NSCollectionView,
			layout collectionViewLayout: NSCollectionViewLayout,
			sizeForItemAt indexPath: IndexPath
		) -> NSSize
		{
			NSSize(
				width: ConversationFlowLayout.contentWidth(in: collectionView.bounds.width),
				height: heights[indexPath.item]
			)
		}
	}
}
