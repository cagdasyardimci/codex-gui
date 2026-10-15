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

	@Test func visibleAttributesMatchEveryIntersectingRowAcrossADeepTranscript() async throws
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
		try await assertVisibleAttributes(
			fixture,
			heights: source.heights
		)
		let previousBottom = fixture.layout.collectionViewContentSize.height
		source.heights[960] += 800
		fixture.layout.invalidateContentMetrics()
		fixture.layout.prepare()
		#expect(fixture.layout.collectionViewContentSize.height > previousBottom)
		try await assertVisibleAttributes(
			fixture,
			heights: source.heights
		)
	}

	@Test func visibleAttributesIncludeTallRowsOverlappingShorterRows() async throws
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
		try await assertVisibleAttributes(
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

	@Test nonisolated func visibilityReferenceMatchesFullScanAtBandBoundariesAndOverlaps() throws
	{
		// Unordered, nested and duplicate frames exercise the reference independently of AppKit.
		let frames = [
			CGRect(
				x: 40,
				y: 128,
				width: 370,
				height: 64
			),
			CGRect(
				x: 40,
				y: -256,
				width: 370,
				height: 128
			),
			CGRect(
				x: 40,
				y: -128,
				width: 370,
				height: 1_024
			),
			CGRect(
				x: 40,
				y: 0,
				width: 370,
				height: 128
			),
			CGRect(
				x: 40,
				y: 128,
				width: 370,
				height: 0
			),
			CGRect(
				x: 40,
				y: 256,
				width: 370,
				height: 150
			),
			CGRect(
				x: 451,
				y: 127,
				width: 30,
				height: 129
			),
			CGRect(
				x: 40,
				y: 0,
				width: 370,
				height: 128
			),
		]
		let snapshot = frames.enumerated().map
		{
			AttributeSnapshot(
				frame: $0.element,
				indexPath: IndexPath(
					item: $0.offset,
					section: 0
				)
			)
		}
		let positions = frames.flatMap
		{
			[$0.minY - 1, $0.minY, $0.minY + 1, $0.maxY - 1, $0.maxY, $0.maxY + 1]
		}
		let rectangles = [CGFloat(0), 40, 451].flatMap
		{
			x in positions.flatMap
			{
				y in [CGFloat(0), 1, 150, 900].map
				{
					CGRect(
						x: x,
						y: y,
						width: 450,
						height: $0
					)
				}
			}
		}
		let reference = Self.visibilityReference(
			snapshot: snapshot,
			rectangles: rectangles
		)
		try #require(reference.queries.count == rectangles.count)
		for (query, rectangle) in zip(
			reference.queries,
			rectangles
		)
		{
			let matching = snapshot.filter
			{
				$0.frame.intersects(rectangle)
			}
			#expect(query.rectangle == rectangle)
			#expect(query.expected == Set(matching.compactMap(\.indexPath)))
			#expect(query.expectedFrames == matching.map(\.frame))
		}
	}

	private struct AttributeSnapshot: Sendable
	{
		let frame: CGRect
		let indexPath: IndexPath?
	}

	private struct VisibilityQuery: Sendable
	{
		let rectangle: CGRect
		let expected: Set<IndexPath>
		let expectedFrames: [CGRect]
	}

	private struct VisibilityReference: Sendable
	{
		let queries: [VisibilityQuery]
		let intersectionChecks: Int
	}

	private nonisolated static func visibilityReference(
		snapshot: [AttributeSnapshot],
		rectangles: [CGRect]
	) -> VisibilityReference
	{
		// Fixed bands avoid the production prefix-max/binary-search visibility index.
		let bandHeight: CGFloat = 128
		func bands(for rectangle: CGRect) -> ClosedRange<Int>
		{
			// Include both ends so touching edges and zero-height rectangles remain candidates.
			// Any intersecting pair shares a band; CGRect.intersects makes the final decision.
			let first = Int((rectangle.minY / bandHeight).rounded(.down))
			let last = Int((rectangle.maxY / bandHeight).rounded(.down))
			return first ... last
		}
		var rowsByBand: [Int: [Int]] = [:]
		for (index, attributes) in snapshot.enumerated()
		{
			for band in bands(for: attributes.frame)
			{
				rowsByBand[band, default: []].append(index)
			}
		}
		var intersectionChecks = 0
		let queries = rectangles.map
		{
			rectangle in
			var candidates: Set<Int> = []
			for band in bands(for: rectangle)
			{
				candidates.formUnion(rowsByBand[band] ?? [])
			}
			// Deduplicate rows spanning bands and retain the full scan's diagnostic frame order.
			let matching = candidates.sorted().compactMap
			{
				index -> AttributeSnapshot? in
				intersectionChecks += 1
				let attributes = snapshot[index]
				return attributes.frame.intersects(rectangle) ? attributes : nil
			}
			return VisibilityQuery(
				rectangle: rectangle,
				expected: Set(matching.compactMap(\.indexPath)),
				expectedFrames: matching.map(\.frame)
			)
		}
		return VisibilityReference(
			queries: queries,
			intersectionChecks: intersectionChecks
		)
	}

	private func assertVisibleAttributes(
		_ fixture: LayoutFixture,
		heights: [CGFloat]
	) async throws
	{
		let snapshot = try heights.indices.map
		{
			let attributes = try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(
				item: $0,
				section: 0
			)))
			return AttributeSnapshot(
				frame: attributes.frame,
				indexPath: attributes.indexPath
			)
		}
		// Keep all queries and an independent reference, while pruning impossible row pairs.
		// Immutable frame values can be checked off MainActor without transferring AppKit objects.
		let reference = try await BackgroundTestWork.perform
		{
			let timing = TestTiming.begin("oracle.prepare")
			defer
			{
				timing.end()
			}
			let rectangles = snapshot.enumerated().flatMap
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
			return Self.visibilityReference(
				snapshot: snapshot,
				rectangles: rectangles
			)
		}
		let timing = TestTiming.begin(
			"native.checks",
			detail: "queries=\(reference.queries.count)"
				+ " intersections=\(reference.intersectionChecks)"
		)
		defer
		{
			timing.end()
		}
		for (index, query) in reference.queries.enumerated()
		{
			let actual = Set(fixture.layout.layoutAttributesForElements(in: query.rectangle)
				.compactMap(\.indexPath))
			#expect(
				actual == query.expected,
				"Rect: \(query.rectangle); expected frames: \(query.expectedFrames)"
			)
			if (index + 1).isMultiple(of: 128)
			{
				// Preserve every native query while sharing the actor between bounded batches.
				// This yield provides fairness; correctness does not depend on elapsed time.
				await Task.yield()
			}
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
