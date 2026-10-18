import Darwin
import Foundation

/// Compiles one search's alternatives and matches contained relative paths without suffix copies.
struct FileSearchMask
{
	private struct Pattern
	{
		let bytes: ContiguousArray<CChar>
		let isRecursive: Bool
		let usesRelativePath: Bool

		init(_ pattern: String)
		{
			isRecursive = pattern.hasPrefix("**/")
			usesRelativePath = pattern.contains("/")
			bytes = (isRecursive ? String(pattern.dropFirst(3)) : pattern).utf8CString
		}
	}

	private let patterns: [Pattern]?

	init(_ mask: String?)
	{
		guard let mask, !mask.isEmpty
		else
		{
			patterns = nil
			return
		}
		patterns = Self.alternatives(mask).map(Pattern.init)
	}

	func matches(_ path: String) -> Bool
	{
		guard let patterns
		else
		{
			return true
		}
		return path.withCString
		{
			pathBytes in
			let name = strrchr(
				pathBytes,
				47
			).map
			{
				UnsafePointer($0.advanced(by: 1))
			} ?? pathBytes
			return patterns.contains
			{
				pattern in pattern.bytes.withUnsafeBufferPointer
				{
					bytes in
					let matchesBasename = pattern.isRecursive || !pattern.usesRelativePath
					let candidate = matchesBasename ? name : pathBytes
					if fnmatch(
						bytes.baseAddress!,
						candidate,
						FNM_CASEFOLD
					) == 0
					{
						return true
					}
					guard pattern.isRecursive
					else
					{
						return false
					}
					var suffix = pathBytes
					while suffix != name
					{
						if fnmatch(
							bytes.baseAddress!,
							suffix,
							FNM_CASEFOLD
						) == 0
						{
							return true
						}
						guard let separator = strchr(
							suffix,
							47
						)
						else
						{
							break
						}
						suffix = UnsafePointer(separator.advanced(by: 1))
					}
					return false
				}
			}
		}
	}

	private static func alternatives(_ mask: String) -> [String]
	{
		guard let open = mask.firstIndex(of: "{"),
				let close = mask[open...].firstIndex(of: "}")
		else
		{
			return mask.split(separator: ",").map
			{
				$0.trimmingCharacters(in: .whitespaces)
			}
		}
		let prefix = String(mask[..<open])
		let suffix = String(mask[mask.index(after: close)...])
		return mask[mask.index(after: open) ..< close].split(separator: ",").prefix(32).map
		{
			prefix + $0.trimmingCharacters(in: .whitespaces) + suffix
		}
	}
}
