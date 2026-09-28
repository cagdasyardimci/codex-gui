#!/usr/bin/env python3
"""Regression checks for the supplemental, token-preserving Swift style pass."""

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("swift-style.py")
SPEC = importlib.util.spec_from_file_location("swift_style", SCRIPT)
STYLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STYLE)


class SwiftStyleTests(unittest.TestCase):
    def format(self, source):
        formatted = STYLE.format_source(source)
        self.assertEqual(STYLE.token_signature(source), STYLE.token_signature(formatted))
        self.assertEqual(formatted, STYLE.format_source(formatted), "Formatting must be idempotent")
        return formatted

    def test_nested_calls_and_declarations(self):
        result = self.format("""func build(a: Int, b: Int) { consume(first: transform(a), second: pair(a, b)) }
""")
        self.assertIn("func build(\n\ta: Int,\n\tb: Int\n)", result)
        self.assertIn("consume(\n\t\tfirst: transform(a),", result)
        self.assertIn("pair(\n", result)

    def test_closure_braces_and_capture_lists(self):
        result = self.format("""let result = items.map { [weak owner] item in owner?.consume(item) }
let empty = { }
""")
        self.assertIn("items.map\n{\n\t[weak owner] item in", result)
        self.assertIn("let empty =\n{\n}", result)

    def test_string_literals_and_interpolation(self):
        source = '''let raw = #"{ foo(a: 1, b: 2) } \\#(foo(a: 1, b: 2))"#
let ordinary = "value \\(foo(a: 1, b: 2))"
let multiline = """
{ literal, body }
"""
let regex = /a{1,2}/
'''
        supplemental = STYLE.supplemental_layout(source)
        self.assertEqual(source, supplemental)
        self.format(source)

    def test_comments_and_blank_lines(self):
        source = """func run() {
    // Keep this { comment, exactly }.
    let first = 1

    /* This { block, remains } intact. */
    consume(a: first, // Attached to first.
            b: 2)
}
"""
        result = self.format(source)
        self.assertIn("// Keep this { comment, exactly }.", result)
        self.assertIn("/* This { block, remains } intact. */", result)
        self.assertIn("first, // Attached to first.", result)
        self.assertIn("let first = 1\n\n", result)

    def test_tuple_types_and_tuple_values_are_not_calls(self):
        source = """let coordinates: (Int, Int) = (1, 2)
let callback: (Int, Int) -> Void
func consume(pair: (Int, Int), callback: (Int, Int) -> Void) { callback(pair.0, pair.1) }
"""
        result = self.format(source)
        self.assertIn("coordinates: (Int, Int) = (1, 2)", result)
        self.assertIn("callback: (Int, Int) -> Void", result)
        self.assertIn("pair: (Int, Int),", result)

    def test_generic_arguments_and_collection_literals(self):
        result = self.format("""let result = consume(values: Dictionary<String, Int>(), fallback: [1, 2])
""")
        self.assertIn("Dictionary<String, Int>()", result)
        self.assertIn("fallback: [1, 2]", result)

    def test_single_argument_compaction_preserves_literals_and_declarations(self):
        result = self.format('''func consume(
    value: String
) { }
setAccessibilityLabel(
    "short label"
)
consume(
    "value \(single(1))"
)
consume(
    nested(
        value
    )
)
''')
        self.assertIn('setAccessibilityLabel("short label")', result)
        self.assertIn('consume("value \\(single(1))")', result)
        self.assertIn("consume(nested(value))", result)
        self.assertIn("func consume(\n\tvalue: String\n)", result)

    def test_continuation_indentation_has_no_spaces_before_tabs(self):
        source = """func run() {
    guard let first = items.first,
          let last = items.last else { return }
    let result = items.map { [weak owner] item in owner?.consume(item) }
    let ready = isFirst ||
                isSecond ||
                isThird
    consume(first: first, last: last)
}
"""
        result = self.format(source)
        for line in result.splitlines():
            indentation = line[:len(line) - len(line.lstrip())]
            self.assertNotIn(" \t", indentation)
        self.assertIn("\n\t\t\tlet last", result)
        self.assertIn("items.map\n\t{\n\t\t[weak owner] item in", result)

    def test_guard_call_and_closure_continuations_use_pure_tabs(self):
        source = """func run() {
    guard process.terminationStatus == 0,
          let version = String(data: versionData, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
          !version.isEmpty else { return }
    guard let entries = result["data"] as? [[String: Any]],
          let entry = entries.first(where: { $0["cwd"] as? String == cwd }),
          let rawSkills = entry["skills"] as? [[String: Any]] else { return }
}
"""
        result = self.format(source)
        self.assertIn("\n\t\t\tdata: versionData,", result)
        for line in result.splitlines():
            indentation = line[:len(line) - len(line.lstrip())]
            self.assertNotIn(" ", indentation)

    def test_literal_and_comment_whitespace_is_preserved_exactly(self):
        source = '''func run() {
    /* Preserve
       body text
    */
    let message = """
      leading spaces
    """
    let interpolated = "value \(consume(a: 1, b: 2))"
}
'''
        result = self.format(source)
        original_regions = [source[start:end] for start, end in STYLE.protected_spans(source)]
        formatted_regions = [result[start:end] for start, end in STYLE.protected_spans(result)]
        self.assertEqual(original_regions, formatted_regions)

    def test_unwrappable_width_requires_manual_fix(self):
        with self.assertRaisesRegex(RuntimeError, "Lines exceed 100 columns"):
            STYLE.format_source('let message = "' + 'x' * 110 + '"\n')

    def test_tabs_and_width_for_wrappable_code(self):
        result = self.format("""func performOperation(firstArgument: String, secondArgument: String) {
    consume(firstArgument: firstArgument, secondArgument: secondArgument)
}
""")
        for line in result.splitlines():
            self.assertFalse(line.startswith(" "), repr(line))
            self.assertLessEqual(len(line.expandtabs(4)), 100)


if __name__ == "__main__":
    unittest.main()
