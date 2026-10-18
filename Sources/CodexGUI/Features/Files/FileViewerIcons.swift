import AppKit

@MainActor
enum FileViewerIcons
{
	/// Raw names come from the dependency's icon catalogue. Absent names use SF Symbols.
	enum Icon: String
	{
		case file = "File"
		case textFile = "FileDocument"
		case configuration = "FileCode"
		case folder = "Folder"
		case navigator = "Folders"
		case fileSearch = "FileSearch"
		case search = "Search"
		case clearSearch = "XCircleFilledCrossedClose"
		case chevronRight = "ChevronSmallRight"
		case chevronDown = "ChevronDown"
		case externalOpen = "ExternalLink"
		case swift = "Swift"
		case symbolicLink = "Link"

		var systemSymbol: String
		{
			switch self
			{
			case .file: "doc"
			case .textFile: "doc.text"
			case .configuration: "curlybraces"
			case .folder, .navigator: "folder"
			case .fileSearch: "doc.text.magnifyingglass"
			case .search: "magnifyingglass"
			case .clearSearch: "xmark.circle.fill"
			case .chevronRight: "chevron.right"
			case .chevronDown: "chevron.down"
			case .externalOpen: "arrow.up.forward.app"
			case .swift: "swift"
			case .symbolicLink: "link"
			}
		}
	}

	static func image(
		_ icon: Icon,
		size: CGFloat = 16,
		accessibilityDescription: String? = nil
	) -> NSImage?
	{
		if icon == .swift
		{
			return WorkspaceFileIcon.swiftImage(
				size: size,
				accessibilityDescription: accessibilityDescription
			)
		}
		if let packaged = DesktopIcon(rawValue: icon.rawValue)
		{
			return DesktopIcons.image(
				packaged,
				size: size,
				accessibilityDescription: accessibilityDescription
			)
		}
		let image = NSImage(
			systemSymbolName: icon.systemSymbol,
			accessibilityDescription: accessibilityDescription
		)
		image?.size = NSSize(
			width: size,
			height: size
		)
		image?.isTemplate = true
		return image
	}

	static func image(for file: WorkspaceFileTypePresentation) -> NSImage?
	{
		WorkspaceFileIcon.image(for: file)
	}

	static func fileImage(
		relativePath: String,
		isDirectory: Bool = false,
		isSymbolicLink: Bool = false,
		size: CGFloat = 16
	) -> NSImage
	{
		WorkspaceFileIcon.image(
			relativePath: relativePath,
			isDirectory: isDirectory,
			isSymbolicLink: isSymbolicLink,
			size: size
		)
	}

}
