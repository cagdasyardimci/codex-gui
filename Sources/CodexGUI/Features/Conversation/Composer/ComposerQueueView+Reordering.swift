import AppKit

extension ComposerQueueView
{
	@discardableResult
	func beginReordering(
		_ row: ComposerQueueRow,
		at point: NSPoint
	) -> Bool
	{
		guard reorderSession == nil, row.canDrag, row.queueView === self,
				let presentation, presentation.reservedQueuedMessageIDs.isEmpty,
				let index = rows.arrangedSubviews.firstIndex(of: row),
				let first = messageRows.first, window != nil
		else
		{
			return false
		}
		queueMenu?.close()
		clearActionHovers()
		rows.layoutSubtreeIfNeeded()
		let frame = convert(
			row.bounds,
			from: row
		)
		let placeholder = NSView()
		placeholder.setAccessibilityElement(false)
		let session = ComposerQueueDragSession(
			row: row,
			placeholder: placeholder,
			originalIDs: presentation.queuedMessages.map(\.id),
			originalIndex: index,
			firstCenter: first.frame.midY,
			grabOffset: convert(
				point,
				from: nil
			).y - frame.minY
		)
		reorderSession = session
		rows.removeArrangedSubview(row)
		row.removeFromSuperview()
		rows.insertArrangedSubview(
			placeholder,
			at: index
		)
		placeholder.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			placeholder.widthAnchor.constraint(
				equalTo: rows.widthAnchor,
				constant: -(rows.edgeInsets.left + rows.edgeInsets.right)
			),
			placeholder.heightAnchor.constraint(equalToConstant: ComposerQueueRow.rowHeight)
		])
		row.translatesAutoresizingMaskIntoConstraints = true
		addSubview(
			row,
			positioned: .above,
			relativeTo: nil
		)
		row.frame = frame
		row.alphaValue = 0.6
		rows.layoutSubtreeIfNeeded()
		return true
	}

	func updateReordering(
		at point: NSPoint,
		event: NSEvent? = nil
	)
	{
		guard let session = reorderSession, !session.settling
		else
		{
			return
		}
		if let event
		{
			_ = rows.autoscroll(with: event)
		}
		let pointer = convert(
			point,
			from: nil
		)
		session.row.setFrameOrigin(NSPoint(
			x: session.row.frame.minX,
			y: pointer.y - session.grabOffset
		))
		let center = rows.convert(
			NSPoint(
				x: session.row.frame.midX,
				y: session.row.frame.midY
			),
			from: self
		).y
		let pitch = ComposerQueueRow.rowHeight + rows.spacing
		let normalized = (center - session.firstCenter) * (rows.isFlipped ? 1 : -1) / pitch
		let target = min(
			session.originalIDs.count - 1,
			max(
				0,
				Int(floor(normalized + 0.5))
			)
		)
		let headerCount = rows.arrangedSubviews.count - session.originalIDs.count
		let index = headerCount + target
		guard rows.arrangedSubviews.firstIndex(of: session.placeholder) != index
		else
		{
			return
		}
		NSAnimationContext.runAnimationGroup
		{
			context in
			context.duration = reorderAnimationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			context.allowsImplicitAnimation = true
			rows.removeArrangedSubview(session.placeholder)
			session.placeholder.removeFromSuperview()
			rows.insertArrangedSubview(
				session.placeholder,
				at: index
			)
			session.placeholder.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				session.placeholder.widthAnchor.constraint(
					equalTo: rows.widthAnchor,
					constant: -(rows.edgeInsets.left + rows.edgeInsets.right)
				),
			])
			rows.layoutSubtreeIfNeeded()
		}
	}

	func endReordering(at point: NSPoint)
	{
		updateReordering(at: point)
		guard let session = reorderSession, !session.settling
		else
		{
			return
		}
		session.settling = true
		session.row.alphaValue = 1
		let target = convert(
			session.placeholder.bounds,
			from: session.placeholder
		)
		reorderSettlingTask = Task
		{
			@MainActor [weak self] in
			guard let self, self.reorderSession === session, !Task.isCancelled
			else
			{
				return
			}
			await withCheckedContinuation
			{
				continuation in
				NSAnimationContext.runAnimationGroup(
					{
						context in
						context.duration = self.reorderAnimationDuration
						context.timingFunction = CAMediaTimingFunction(name: .easeOut)
						session.row.animator().setFrameOrigin(target.origin)
					},
					completionHandler:
					{
						continuation.resume()
					}
				)
			}
			guard self.reorderSession === session, !Task.isCancelled,
					let index = self.rows.arrangedSubviews.firstIndex(of: session.placeholder)
			else
			{
				return
			}
			self.restoreDraggedRow(
				session,
				at: index
			)
			self.reorderSession = nil
			self.reorderSettlingTask = nil
			let ids = self.messageRows.map
			{
				$0.message.id
			}
			if ids != session.originalIDs
			{
				self.pendingVisualOrder = ids
				self.onReorder?(ids)
			}
		}
	}

	func cancelReordering()
	{
		guard let session = reorderSession
		else
		{
			return
		}
		reorderSettlingTask?.cancel()
		reorderSettlingTask = nil
		reorderSession = nil
		session.row.layer?.removeAllAnimations()
		restoreDraggedRow(
			session,
			at: session.originalIndex
		)
	}

	private var reorderAnimationDuration: TimeInterval
	{
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
	}

	private func restoreDraggedRow(
		_ session: ComposerQueueDragSession,
		at index: Int
	)
	{
		rows.removeArrangedSubview(session.placeholder)
		session.placeholder.removeFromSuperview()
		session.row.removeFromSuperview()
		rows.insertArrangedSubview(
			session.row,
			at: min(
				index,
				rows.arrangedSubviews.count
			)
		)
		session.row.translatesAutoresizingMaskIntoConstraints = false
		session.row.widthAnchor.constraint(
			equalTo: rows.widthAnchor,
			constant: -(rows.edgeInsets.left + rows.edgeInsets.right)
		).isActive = true
		session.row.alphaValue = 1
		rows.layoutSubtreeIfNeeded()
	}
}
