import AppKit

/// Complete repeatable text or key/value field with add/remove controls and literal values.
@MainActor
final class SettingsFormEntriesField: NSStackView
{
	enum Format: Equatable
	{
		case lines
		case pairs
	}

	private struct Entry
	{
		let first: String
		let second: String?
	}

	private struct Row
	{
		let view: SettingsFormEntryRow
		let width: NSLayoutConstraint
	}

	var onChange: (() -> Void)?
	private let format: Format
	private let item: String
	private let add: DesktopActionButton
	private var rows: [Row] = []

	init(
		format: Format,
		item: String,
		addTitle: String
	)
	{
		self.format = format
		self.item = item
		add = DesktopActionButton(
			title: addTitle,
			presentation: .secondary
		)
		super.init(frame: .zero)
		orientation = .vertical
		alignment = .leading
		spacing = 12
		add.onAction =
		{
			[weak self] in self?.addEntry()
		}
		addArrangedSubview(add)
		stringValue = ""
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	var stringValue: String
	{
		get
		{
			rows.compactMap
			{
				row in
				let first = row.view.firstValue
				guard let second = row.view.secondValue
				else
				{
					return first.isEmpty ? nil : first
				}
				return first.isEmpty && second.isEmpty ? nil : "\(first)=\(second)"
			}.joined(separator: "\n")
		}
		set
		{
			let entries = newValue.components(separatedBy: .newlines).filter
			{
				!$0.isEmpty
			}.map
			{
				line -> Entry in
				guard format == .pairs
				else
				{
					return Entry(
						first: line,
						second: nil
					)
				}
				guard let split = line.firstIndex(of: "=")
				else
				{
					return Entry(
						first: line,
						second: ""
					)
				}
				return Entry(
					first: String(line[..<split]),
					second: String(line[line.index(after: split)...])
				)
			}
			rebuild(entries.isEmpty
				? [Entry(
					first: "",
					second: format == .pairs ? "" : nil
				)]
				: entries)
		}
	}

	private func rebuild(_ entries: [Entry])
	{
		for row in rows
		{
			row.width.isActive = false
			removeArrangedSubview(row.view)
			row.view.removeFromSuperview()
		}
		rows.removeAll()
		for entry in entries
		{
			append(entry)
		}
		updateRemoveButtons()
	}

	private func append(_ entry: Entry)
	{
		let row = SettingsFormEntryRow(
			firstValue: entry.first,
			secondValue: entry.second,
			item: item
		)
		row.onChange =
		{
			[weak self] in self?.onChange?()
		}
		row.onRemove =
		{
			[weak self, weak row] in
			guard let self, let row,
					let index = self.rows.firstIndex(where:
					{
						$0.view === row
					})
			else
			{
				return
			}
			self.removeEntry(at: index)
		}
		insertArrangedSubview(
			row,
			at: rows.count
		)
		let width = row.widthAnchor.constraint(equalTo: widthAnchor)
		width.isActive = true
		rows.append(Row(
			view: row,
			width: width
		))
	}

	private func updateRemoveButtons()
	{
		for (index, row) in rows.enumerated()
		{
			row.view.updatePosition(
				index + 1,
				canRemove: rows.count > 1
			)
		}
	}

	private func addEntry()
	{
		append(Entry(
			first: "",
			second: format == .pairs ? "" : nil
		))
		updateRemoveButtons()
		onChange?()
	}

	private func removeEntry(at index: Int)
	{
		guard rows.count > 1, rows.indices.contains(index)
		else
		{
			return
		}
		let row = rows.remove(at: index)
		row.width.isActive = false
		removeArrangedSubview(row.view)
		row.view.removeFromSuperview()
		updateRemoveButtons()
		onChange?()
	}

}
