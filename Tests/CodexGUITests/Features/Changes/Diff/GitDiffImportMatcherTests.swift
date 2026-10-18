import Testing

@testable import CodexGUI

struct GitDiffImportMatcherTests
{
	@Test(arguments: ["Source.swift", "Source.SWIFT"])
	func swiftImportsRetainTheLimitedSyntaxPolicy(path: String) throws
	{
		let matcher = try #require(GitDiffImportMatcher(path: path))
		for text in ["import Foundation",
						"import App.Kit",
						"@testable import CodexGUI",
						"@_exported import A",
						"@_implementationOnly import A",
						"import A \t"]
		{
			#expect(
				matcher.matches(text),
				"Expected Swift import: \(text)"
			)
		}
		for text in [" import A",
						"import A // explanation",
						"import struct A.Value",
						"import Café",
						"import A; run()",
						"run()",
						"@testable  import A"]
		{
			#expect(
				!matcher.matches(text),
				"Expected visible source: \(text)"
			)
		}
	}

	@Test(arguments: ["source.py", "source.pyw", "SOURCE.PY"])
	func pythonImportsRetainAliasesAndRelativeModules(path: String) throws
	{
		let matcher = try #require(GitDiffImportMatcher(path: path))
		for text in ["import alpha",
						"import alpha as a, beta.sub as b",
						"from . import value",
						"from ..alpha import value as v, other",
						"from alpha import *",
						"import alpha \t"]
		{
			#expect(
				matcher.matches(text),
				"Expected Python import: \(text)"
			)
		}
		for text in [" import alpha",
						"import alpha # explanation",
						"from alpha import (value,",
						"from alpha import value,",
						"import α",
						"run()",
						"import alpha; run()"]
		{
			#expect(
				!matcher.matches(text),
				"Expected visible source: \(text)"
			)
		}
	}

	@Test(arguments: ["source.txt", "source.js", "source.swift.txt", "Makefile"])
	func otherLanguagesHaveNoImportFilter(path: String)
	{
		#expect(GitDiffImportMatcher(path: path) == nil)
	}
}
