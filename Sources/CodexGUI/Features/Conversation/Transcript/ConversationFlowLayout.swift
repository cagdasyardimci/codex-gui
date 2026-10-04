import AppKit

@MainActor
final class ConversationFlowLayout: NSCollectionViewFlowLayout
{
	static let maximumContentWidth: CGFloat = 736
	static let minimumHorizontalInset: CGFloat = 16
	private var preparedWidth: CGFloat?
	private var updatingCenteringInsets = false
	var verticalGap: ((Int) -> CGFloat)?
	var willChangeContentWidth: (([NSCollectionViewLayoutAttributes]) -> Void)?
	private var compactAttributes: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
	private var verticallyOrderedAttributes: [NSCollectionViewLayoutAttributes] = []
	private var prefixMaximumY: [CGFloat] = []
	private var compactContentSize: NSSize?

	static func contentWidth(in availableWidth: CGFloat) -> CGFloat
	{
		max(
			1,
			min(
				maximumContentWidth,
				availableWidth - 2 * minimumHorizontalInset
			)
		)
	}

	override func prepare()
	{
		updateCenteredContentWidth()
		compactAttributes.removeAll(keepingCapacity: true)
		verticallyOrderedAttributes.removeAll(keepingCapacity: true)
		prefixMaximumY.removeAll(keepingCapacity: true)
		compactContentSize = nil
		super.prepare()
		prepareCompactActivitySpacing()
	}

	private func updateCenteredContentWidth()
	{
		// A clip-view frame change can reach prepare after the collection's bounds
		// already changed. Compare against the width used for the cached metrics.
		if let width = collectionView?.bounds.width, width != preparedWidth
		{
			if preparedWidth != nil
			{
				willChangeContentWidth?(verticallyOrderedAttributes)
			}
			preparedWidth = width
			let horizontalInset = max(
				Self.minimumHorizontalInset,
				(width - Self.maximumContentWidth) / 2
			)
			updatingCenteringInsets = true
			sectionInset = NSEdgeInsets(
				top: 20,
				left: horizontalInset,
				bottom: 28,
				right: horizontalInset
			)
			updatingCenteringInsets = false
			let context = NSCollectionViewFlowLayoutInvalidationContext()
			// Section insets are cached delegate metrics too. Even above the reading
			// cap, refresh them so rows move to the new centered origin. Item sizes
			// still reuse their width-keyed measurements in the controller.
			context.invalidateFlowLayoutDelegateMetrics = true
			context.invalidateFlowLayoutAttributes = true
			invalidateLayout(with: context)
		}
	}

	private func prepareCompactActivitySpacing()
	{
		guard let collectionView, let verticalGap
		else
		{
			return
		}
		var removedSpacing: CGFloat = 0
		var requiresSorting = false
		for index in 0 ..< collectionView.numberOfItems(inSection: 0)
		{
			let path = IndexPath(
				item: index,
				section: 0
			)
			guard let original = super.layoutAttributesForItem(at: path),
					let attributes = original.copy() as? NSCollectionViewLayoutAttributes
			else
			{
				continue
			}
			if index > 0
			{
				removedSpacing += minimumLineSpacing - verticalGap(index)
			}
			attributes.frame.origin.y -= removedSpacing
			compactAttributes[path] = attributes
			if let previous = verticallyOrderedAttributes.last,
				previous.frame.minY > attributes.frame.minY
			{
				requiresSorting = true
			}
			verticallyOrderedAttributes.append(attributes)
		}
		if requiresSorting
		{
			verticallyOrderedAttributes.sort
			{
				$0.frame.minY < $1.frame.minY
			}
		}
		var maximumY = -CGFloat.infinity
		for attributes in verticallyOrderedAttributes
		{
			maximumY = max(
				maximumY,
				attributes.frame.maxY
			)
			prefixMaximumY.append(maximumY)
		}
		let originalSize = super.collectionViewContentSize
		compactContentSize = NSSize(
			width: originalSize.width,
			height: max(
				0,
				originalSize.height - removedSpacing
			)
		)
	}

	override var collectionViewContentSize: NSSize
	{
		compactContentSize ?? super.collectionViewContentSize
	}

	override func layoutAttributesForItem(at indexPath: IndexPath)
		-> NSCollectionViewLayoutAttributes?
	{
		compactAttributes[indexPath] ?? super.layoutAttributesForItem(at: indexPath)
	}

	override func layoutAttributesForElements(in rect: NSRect)
		-> [NSCollectionViewLayoutAttributes]
	{
		guard verticalGap != nil
		else
		{
			return super.layoutAttributesForElements(in: rect)
		}
		// Prefix maxima also find a tall overlapping row whose origin is above the
		// viewport. The usual single-column transcript only visits visible rows.
		var lower = 0
		var upper = prefixMaximumY.count
		while lower < upper
		{
			let middle = lower + (upper - lower) / 2
			if prefixMaximumY[middle] < rect.minY
			{
				lower = middle + 1
			}
			else
			{
				upper = middle
			}
		}
		var visible: [NSCollectionViewLayoutAttributes] = []
		for index in lower ..< verticallyOrderedAttributes.count
		{
			let attributes = verticallyOrderedAttributes[index]
			// A zero-height Foundation rect intersects the row's leading edge.
			// Leave boundary inclusion to intersects after the conservative scan.
			guard attributes.frame.minY <= rect.maxY
			else
			{
				break
			}
			if attributes.frame.intersects(rect)
			{
				visible.append(attributes)
			}
		}
		return visible
	}

	override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool
	{
		widthChanges(to: newBounds) || super.shouldInvalidateLayout(forBoundsChange: newBounds)
	}

	override func invalidationContext(forBoundsChange newBounds: NSRect)
		-> NSCollectionViewLayoutInvalidationContext
	{
		let context = super.invalidationContext(forBoundsChange: newBounds)
		if widthChanges(to: newBounds),
			let flowContext = context as? NSCollectionViewFlowLayoutInvalidationContext
		{
			flowContext.invalidateFlowLayoutDelegateMetrics = true
			flowContext.invalidateFlowLayoutAttributes = true
		}
		return context
	}

	private func widthChanges(to bounds: NSRect) -> Bool
	{
		preparedWidth != bounds.width
	}

	override func invalidateLayout()
	{
		if updatingCenteringInsets
		{
			let context = NSCollectionViewFlowLayoutInvalidationContext()
			context.invalidateFlowLayoutDelegateMetrics = true
			context.invalidateFlowLayoutAttributes = true
			super.invalidateLayout(with: context)
		}
		else
		{
			super.invalidateLayout()
		}
	}

	override func invalidateLayout(with context: NSCollectionViewLayoutInvalidationContext)
	{
		if updatingCenteringInsets,
			let flowContext = context as? NSCollectionViewFlowLayoutInvalidationContext
		{
			flowContext.invalidateFlowLayoutDelegateMetrics = true
		}
		super.invalidateLayout(with: context)
	}

	func invalidateContentMetrics()
	{
		let context = NSCollectionViewFlowLayoutInvalidationContext()
		context.invalidateFlowLayoutDelegateMetrics = true
		context.invalidateFlowLayoutAttributes = true
		invalidateLayout(with: context)
	}

	func invalidateContentAttributes()
	{
		let context = NSCollectionViewFlowLayoutInvalidationContext()
		context.invalidateFlowLayoutDelegateMetrics = false
		context.invalidateFlowLayoutAttributes = true
		invalidateLayout(with: context)
	}
}
