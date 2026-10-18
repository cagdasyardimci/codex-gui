#!/usr/bin/env python3
"""Apply SwiftFormat plus the repository's closure and argument layout conventions.

SwiftFormat supplies the lexer and indentation. The supplemental pass edits only
whitespace outside comments and string literals (including interpolated code).
"""

import argparse
import concurrent.futures
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TRIVIA = {"space", "linebreak"}
NON_CALL_KEYWORDS = {
    "if", "while", "switch", "for", "guard", "catch", "return", "throw",
    "case", "let", "var", "as", "is", "some", "any", "await", "try",
}


def run_swiftformat(source, arguments):
    result = subprocess.run(
        ["swiftformat", "stdin", *arguments, "--quiet"],
        input=source,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "SwiftFormat failed")
    return result.stdout


def tokenize(source):
    return json.loads(run_swiftformat(
        source, ["--disable", "all", "--output-tokens"]
    ))["tokens"]


def token_signature(source):
    # Whitespace changes are permitted; lexemes, literals, and comment bodies are not.
    return [(token["type"], token["string"]) for token in tokenize(source)
            if token["type"] not in TRIVIA]


def scope_information(tokens):
    """Find structural pairs and protect complete literal and comment scopes."""
    pairs = {}
    protected = set()
    stack = []
    line_comment = False
    for index, token in enumerate(tokens):
        kind, value = token["type"], token["string"]
        if line_comment:
            if kind == "linebreak":
                line_comment = False
            else:
                protected.add(index)
                continue
        if value == "//" and kind == "startOfScope":
            protected.add(index)
            line_comment = True
            continue
        if any(is_protected for _, is_protected in stack):
            protected.add(index)
        if kind == "startOfScope":
            is_protected = value not in {"(", "[", "{", "<", ":", "#if"}
            stack.append((index, is_protected))
            if is_protected:
                protected.add(index)
        elif kind == "endOfScope" and stack:
            opening, _ = stack.pop()
            pairs[opening] = index
            pairs[index] = opening
    return pairs, protected


def supplemental_layout(source):
    tokens = tokenize(source)
    pairs, protected = scope_information(tokens)
    insertions = set()

    def previous_code(index):
        index -= 1
        while index >= 0 and (tokens[index]["type"] in TRIVIA or index in protected):
            index -= 1
        return tokens[index] if index >= 0 else None

    def break_before(index):
        # Boundary indices refer to immutable tokens; whitespace is normalized later.
        insertions.add(index)

    def break_after(index):
        next_index = index + 1
        while next_index < len(tokens) and tokens[next_index]["type"] == "space":
            next_index += 1
        # Keep end-of-line comments with the statement they describe.
        if next_index < len(tokens) and tokens[next_index]["string"] == "//":
            while next_index < len(tokens) and tokens[next_index]["type"] != "linebreak":
                next_index += 1
        insertions.add(next_index)

    for index, token in enumerate(tokens):
        if index in protected:
            continue
        value, kind = token["string"], token["type"]
        if value == "{" and kind == "startOfScope":
            break_before(index)
            break_after(index)
        elif value == "}" and kind == "endOfScope":
            break_before(index)
        elif value == "(" and kind == "startOfScope" and index in pairs:
            previous = previous_code(index)
            is_call = previous and (
                previous["type"] == "identifier"
                or previous["string"] in {")", "]", ">", "init", "subscript"}
                or (previous["type"] == "keyword"
                    and previous["string"] not in NON_CALL_KEYWORDS)
            )
            if not is_call:
                continue
            closing = pairs[index]
            commas = []
            cursor = index + 1
            while cursor < closing:
                current = tokens[cursor]
                if cursor in protected:
                    cursor += 1
                elif current["type"] == "startOfScope" and cursor in pairs:
                    cursor = pairs[cursor] + 1
                else:
                    if current["string"] == "," and current["type"] == "delimiter":
                        commas.append(cursor)
                    cursor += 1
            if commas:
                break_after(index)
                for comma in commas:
                    break_after(comma)
                break_before(closing)

    # Normalize only the whitespace at requested boundaries. Retain existing
    # blank lines so the author's meaningful phases survive formatting.
    for boundary in sorted(insertions, reverse=True):
        start = boundary
        while start > 0 and tokens[start - 1]["type"] == "space" and start - 1 not in protected:
            start -= 1
        end = boundary
        while end < len(tokens) and tokens[end]["type"] == "space" and end not in protected:
            end += 1
        has_linebreak = (
            start > 0 and tokens[start - 1]["type"] == "linebreak"
        ) or (end < len(tokens) and tokens[end]["type"] == "linebreak")
        if not has_linebreak and start > 0:
            tokens[start:end] = [{"type": "linebreak", "string": "\n"}]
    return "".join(token["string"] for token in tokens)




def protected_spans(source):
    """Locate complete raw literal and comment text, including their whitespace."""
    tokens = tokenize(source)
    _, protected = scope_information(tokens)
    spans = []
    offset = 0
    beginning = None
    for index, token in enumerate(tokens):
        if index in protected and beginning is None:
            beginning = offset
        elif index not in protected and beginning is not None:
            spans.append((beginning, offset))
            beginning = None
        offset += len(token["string"])
    if beginning is not None:
        spans.append((beginning, offset))
    return spans


def restore_protected_text(original, formatted):
    # SwiftFormat can rebase multiline-literal or block-comment indentation even
    # with indent-strings disabled. Preserve their entire original lexical scopes.
    original_spans = protected_spans(original)
    formatted_spans = protected_spans(formatted)
    if len(original_spans) != len(formatted_spans):
        raise RuntimeError("Formatting changed literal/comment scopes; refusing to write")
    for original_span, formatted_span in reversed(list(zip(original_spans, formatted_spans))):
        original_start, original_end = original_span
        formatted_start, formatted_end = formatted_span
        formatted = (formatted[:formatted_start] + original[original_start:original_end]
                     + formatted[formatted_end:])
    return formatted


def compact_single_argument_calls(source):
    """Remove boundary wrapping when a one-line call argument fits comfortably."""
    while True:
        tokens = tokenize(source)
        pairs, protected = scope_information(tokens)
        changed = False
        for opening in sorted(pairs, reverse=True):
            if (opening in protected or tokens[opening]["string"] != "("
                    or tokens[opening]["type"] != "startOfScope"):
                continue
            closing = pairs[opening]
            previous = opening - 1
            while previous >= 0 and tokens[previous]["type"] in TRIVIA:
                previous -= 1
            if previous < 0:
                continue
            caller = tokens[previous]
            if caller["type"] != "identifier" and caller["string"] not in {")", "]", ">", "init"}:
                continue
            before_caller = previous - 1
            while before_caller >= 0 and tokens[before_caller]["type"] in TRIVIA:
                before_caller -= 1
            preceding = tokens[before_caller]["string"] if before_caller >= 0 else ""
            is_declaration = preceding in {"func", "case"} or (
                caller["string"] == "init" and preceding != "."
            )
            if is_declaration:
                continue
            first, last = opening + 1, closing
            while first < last and tokens[first]["type"] in TRIVIA:
                first += 1
            while last > first and tokens[last - 1]["type"] in TRIVIA:
                last -= 1
            if first == last:
                continue
            argument = "".join(token["string"] for token in tokens[first:last])
            has_comment = any(token["type"] == "commentBody" or (token["type"] == "startOfScope"
                                                               and token["string"] in {"//", "/*"})
                              for token in tokens[first:last])
            if "\n" in argument or "\r" in argument or has_comment:
                continue
            cursor = first
            has_comma = False
            while cursor < last:
                token = tokens[cursor]
                if token["type"] == "startOfScope" and cursor in pairs:
                    cursor = pairs[cursor] + 1
                    continue
                if token["type"] == "delimiter" and token["string"] == ",":
                    has_comma = True
                    break
                cursor += 1
            if has_comma:
                continue
            prefix = "".join(token["string"] for token in tokens[:opening + 1]).rsplit("\n", 1)[-1]
            suffix = "".join(token["string"] for token in tokens[closing:]).split("\n", 1)[0]
            if len((prefix + argument + suffix).expandtabs(4)) > 100:
                continue
            if first == opening + 1 and last == closing:
                continue
            # Perform one replacement before re-lexing, so nested scopes never
            # rely on stale token indices and compaction reaches a fixed point.
            tokens[opening + 1:closing] = tokens[first:last]
            source = "".join(token["string"] for token in tokens)
            changed = True
            break
        if not changed:
            return source



def normalize_code_indentation(source):
    """Use tabs for code indentation while freezing literal/comment interiors."""
    tokens = tokenize(source)
    _, protected = scope_information(tokens)
    at_line_start = True
    for index, token in enumerate(tokens):
        kind = token["type"]
        if kind == "linebreak":
            at_line_start = True
        elif kind == "space" and at_line_start:
            if index not in protected:
                width = len(token["string"].expandtabs(4))
                token["string"] = "\t" * ((width + 3) // 4)
        else:
            at_line_start = False
    return "".join(token["string"] for token in tokens)


def format_source(source, config=ROOT / ".swiftformat"):
    arguments = ["--config", str(config)]
    formatted = run_swiftformat(source, arguments)
    formatted = supplemental_layout(formatted)
    formatted = compact_single_argument_calls(formatted)
    formatted = run_swiftformat(formatted, arguments)
    formatted = restore_protected_text(source, formatted)
    formatted = normalize_code_indentation(formatted)
    if token_signature(source) != token_signature(formatted):
        raise RuntimeError("Formatting changed non-whitespace Swift tokens; refusing to write")
    overlong = [str(number) for number, line in enumerate(formatted.splitlines(), 1)
                if len(line.expandtabs(4)) > 100]
    if overlong:
        raise RuntimeError("Lines exceed 100 columns after formatting: " + ", ".join(overlong))
    return formatted


def swift_files(paths):
    files = set()
    for path in paths:
        path = Path(path)
        if path.is_dir():
            files.update(path.rglob("*.swift"))
        elif path.is_file() and path.suffix == ".swift":
            files.add(path)
        else:
            raise ValueError(f"Not a Swift file or directory: {path}")
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check without writing files")
    parser.add_argument("paths", nargs="*", help="Swift files or directories")
    options = parser.parse_args()
    if not shutil.which("swiftformat"):
        parser.error("swiftformat is required; see .swiftformat for the minimum supported version")
    try:
        files = swift_files(options.paths or [ROOT / "Package.swift", ROOT / "Sources", ROOT / "Tests"])
        # Workers only compute results. Writes and error reporting stay ordered here.
        def process(path):
            source = path.read_text()
            try:
                return path, source, format_source(source)
            except RuntimeError as error:
                raise RuntimeError(f"{path}: {error}") from error

        changed = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            for path, source, formatted in executor.map(process, files):
                if source == formatted:
                    continue
                changed += 1
                print(f"{'Needs formatting' if options.check else 'Formatted'}: {path}")
                if not options.check:
                    path.write_text(formatted)
        print(f"Checked {len(files)} Swift files; {changed} {'need formatting' if options.check else 'formatted'}.")
        return 1 if options.check and changed else 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Swift style: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
