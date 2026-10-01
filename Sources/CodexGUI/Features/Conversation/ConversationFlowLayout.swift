import AppKit

@MainActor
final class ConversationFlowLayout: NSCollectionViewFlowLayout
{
	static let maximumContentWidth: CGFloat = 736
	static let minimumHorizontalInset: CGFloat = 16
	private var preparedWidth: CGFloat?
	private var updatingCenteringInsets = false
	var verticalGap: ((Int) -> CGFloat)?
	private var compactAttributes: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
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
		// A clip-view frame change can reach prepare after the collection's bounds
		// already changed. Compare against the width used for the cached metrics.
		if let width = collectionView?.bounds.width, width != preparedWidth
		{
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
		compactAttributes.removeAll()
		compactContentSize = nil
		super.prepare()
		guard let collectionView, let verticalGap
		else
		{
			return
		}
		var removedSpacing: CGFloat = 0
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
		return compactAttributes.values.filter
		{
			$0.frame.intersects(rect)
		}
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
}
