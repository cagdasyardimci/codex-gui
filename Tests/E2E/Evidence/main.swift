import Foundation
import ImageIO
import Vision
import zlib

// Validate exported XCTest evidence and write local reports; Make owns collection.
typealias Object = [String: Any]
enum EvidenceError: Error
{
	case invalid(String)
}
func read(_ url: URL) throws -> Any
{
	try JSONSerialization.jsonObject(with: Data(contentsOf: url))
}
func object(_ url: URL) throws -> Object
{
	guard let value = try read(url) as? Object
	else
	{
		throw EvidenceError.invalid("Expected JSON object: \(url.path)")
	}
	return value
}
func write(
	_ value: Any,
	_ url: URL
) throws
{
	try JSONSerialization.data(
		withJSONObject: value,
		options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	).write(
		to: url,
		options: .atomic
	)
}
func text(
	_ value: Object,
	_ key: String
) -> String
{
	value[key] as? String ?? ""
}
func number(
	_ value: Object,
	_ key: String
) -> Double
{
	(value[key] as? NSNumber)?.doubleValue ?? .nan
}
func integer(
	_ value: Object,
	_ key: String
) -> Int
{
	(value[key] as? NSNumber)?.intValue ?? -1
}
func bool(
	_ value: Object,
	_ key: String
) -> Bool
{
	value[key] as? Bool ?? false
}
func pngDimensions(_ url: URL) throws -> (Int, Int)
{
	let bytes = [UInt8](try Data(contentsOf: url))
	guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
	else
	{
		throw EvidenceError.invalid("invalid PNG signature")
	}
	func uint(_ offset: Int) -> Int
	{
		bytes[offset ..< offset + 4].reduce(0)
		{
			$0 << 8 | Int($1)
		}
	}
	var offset = 8, width = 0, height = 0, ended = false, idat = Data()
	var depth = 0, color = 0, interlace = 0
	let depths = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]
	while offset < bytes.count
	{
		guard bytes.count - offset >= 12
		else
		{
			throw EvidenceError.invalid("truncated PNG chunk")
		}
		let length = uint(offset), end = offset + 8 + length
		guard end <= bytes.count - 4
		else
		{
			throw EvidenceError.invalid("truncated PNG data")
		}
		let kind = String(
			decoding: bytes[offset + 4 ..< offset + 8],
			as: UTF8.self
		)
		let crcData = Data(bytes[offset + 4 ..< end])
		let crc = crcData.withUnsafeBytes
		{
			crc32(
				0,
				$0.bindMemory(to: Bytef.self).baseAddress,
				uInt($0.count)
			)
		}
		guard crc == uint(end)
		else
		{
			throw EvidenceError.invalid("PNG chunk checksum mismatch")
		}
		if width == 0
		{
			guard kind == "IHDR",
					length == 13
			else
			{
				throw EvidenceError.invalid("missing PNG image header")
			}
			width = uint(offset + 8); height = uint(offset + 12)
			depth = Int(bytes[offset + 16]); color = Int(bytes[offset + 17]); interlace =
				Int(bytes[offset + 20])
			guard width > 0, height > 0, depths[color]?.contains(depth) == true,
					bytes[offset + 18] == 0, bytes[offset + 19] == 0,
					interlace <= 1
			else
			{
				throw EvidenceError.invalid("invalid PNG image header")
			}
		}
		else if kind == "IHDR"
		{
			throw EvidenceError.invalid("duplicate PNG image header")
		}
		if kind == "IDAT"
		{
			idat.append(contentsOf: bytes[offset + 8 ..< end])
		}
		if kind == "IEND"
		{
			guard length == 0,
					end + 4 == bytes.count
			else
			{
				throw EvidenceError.invalid("invalid PNG end")
			}
			ended = true; break
		}
		offset = end + 4
	}
	guard ended,
			!idat.isEmpty
	else
	{
		throw EvidenceError.invalid("PNG pixels or end chunk missing")
	}
	let channels = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][color]!
	let rowSize = (width * depth * channels + 7) / 8 + 1
	guard rowSize <= 256_000_000 / height
	else
	{
		throw EvidenceError.invalid("PNG pixel allocation exceeds evidence limit")
	}
	// Interlaced images include per-pass row prefixes; leave bounded extra room.
	var pixels = [UInt8](
		repeating: 0,
		count: rowSize * height + (interlace == 1 ? height * 8 + 1024 : 0)
	)
	var count = uLongf(pixels.count)
	let status = idat.withUnsafeBytes
	{
		data in pixels.withUnsafeMutableBytes
		{
			output in
			uncompress(
				output.bindMemory(to: Bytef.self).baseAddress,
				&count,
				data.bindMemory(to: Bytef.self).baseAddress,
				uLong(data.count)
			)
		}
	}
	guard status == Z_OK,
			count > 0
	else
	{
		throw EvidenceError.invalid("invalid compressed PNG pixels")
	}
	if interlace == 0
	{
		guard count == rowSize * height,
				stride(
				from: 0,
				to: Int(count),
				by: rowSize
				).allSatisfy(
				{
					pixels[$0] <= 4
				}
				)
		else
		{
			throw EvidenceError.invalid("invalid PNG pixel rows")
		}
	}
	guard let source = CGImageSourceCreateWithURL(
		url as CFURL,
		nil
	),
		CGImageSourceCreateImageAtIndex(
			source,
			0,
			nil
		) != nil
	else
	{
		throw EvidenceError.invalid("PNG pixels could not be decoded")
	}
	return (width, height)
}
func attachmentURL(
	_ run: URL,
	_ attachment: Object
) throws -> URL
{
	let name = text(
		attachment,
		"exportedFileName"
	)
	guard !name.isEmpty, !name.contains("/"),
			name != ".."
	else
	{
		throw EvidenceError.invalid("Invalid attachment file name")
	}
	return run.appendingPathComponent("attachments").appendingPathComponent(name)
}
func checkpointValidation(
	_ run: URL,
	attachments: [Object],
	checkpoints: [Object]
) -> ([Object], [String])
{
	var values: [Object] = [], errors: [String] = []
	for checkpoint in checkpoints
	{
		let label = text(
			checkpoint,
			"suggestedHumanReadableName"
		)
		let prefix = label.components(separatedBy: "-checkpoint")[0]
		do
		{
			var details = try object(attachmentURL(
				run,
				checkpoint
			))
			let related = attachments
				.filter
				{
					text(
						$0,
						"suggestedHumanReadableName"
					).hasPrefix(prefix + "-")
				}
			func matches(_ kind: String) -> [Object]
			{
				related.filter
				{
					text(
						$0,
						"suggestedHumanReadableName"
					).contains("-" + kind)
				}
			}
			for kind in [
				"application_",
				"screen_",
				"ui-hierarchy",
				"state-history",
				"fixture",
				"failure-context"
			]
			{
				let found = matches(kind)
				guard found.count == 1
				else
				{
					errors.append(prefix + ": expected one " + kind + " attachment"); continue
				}
				let url = try attachmentURL(
					run,
					found[0]
				); let data = try Data(contentsOf: url)
				if data.isEmpty
				{
					errors.append(prefix + ": empty " + kind + " attachment")
				}
				if ["application_", "screen_"].contains(kind)
				{
					do
					{
						let (width, height) = try pngDimensions(url)
						if kind == "application_",
							let recorded = details["applicationImagePixels"] as? Object,
							(integer(
							recorded,
							"width"
							) != width || integer(
							recorded,
							"height"
							) !=
							height)
						{
							errors.append(prefix + ": image dimensions do not match checkpoint")
						}
					}
					catch
					{
						errors
							.append(prefix + ": invalid PNG for " + kind + ": " +
								String(describing: error))
					}
				}
				if kind == "state-history"
				{
					guard let history = try read(url) as? [Object],
							let last = history.last
					else
					{
						throw EvidenceError.invalid("Empty state history")
					}
					if !(number(
						last,
						"time"
					) <= number(
						details,
						"captureFinished"
					) + 1)
					{
						errors.append(prefix + ": invalid state observation time")
					}
					let age = number(
						details,
						"captureStarted"
					) - number(
						last,
						"time"
					)
					if age > 5
					{
						details["stateAgeSeconds"] = age
					}
				}
			}
			if integer(
				details,
				"schemaVersion"
			) >= 2
			{
				let before = matches("state-history"), after = matches("state-after")
				if before.count != 1 || after
					.count !=
					1
				{
					errors.append(prefix + ": expected one state correlation attachment")
				}
				else
				{
					let beforeData = try Data(contentsOf: attachmentURL(
						run,
						before[0]
					)),
						afterData = try Data(contentsOf: attachmentURL(
							run,
							after[0]
						))
					let beforeValues = try JSONSerialization
						.jsonObject(with: beforeData) as? [Object]
					let afterValues = try JSONSerialization.jsonObject(with: afterData) as? [Object]
					guard let first = beforeValues?.last,
							let last = afterValues?.last
					else
					{
						throw EvidenceError.invalid("Empty state correlation history")
					}
					let beforeSequence = details["stateSequenceBefore"] as? NSNumber,
						afterSequence = details["stateSequenceAfter"] as? NSNumber
					let changed = details["stateChangedDuringCapture"] as? NSNumber
					if beforeSequence == nil || afterSequence == nil || changed == nil ||
						CFGetTypeID(beforeSequence!) == CFBooleanGetTypeID() ||
						CFGetTypeID(afterSequence!) == CFBooleanGetTypeID() ||
						CFGetTypeID(changed!) != CFBooleanGetTypeID() ||
						beforeSequence != first["sequence"] as? NSNumber || afterSequence !=
						last["sequence"] as? NSNumber || changed?
						.boolValue != (beforeData != afterData)
					{
						errors
							.append(prefix +
								": state correlation does not match attached snapshots")
					}
					if !(number(
						last,
						"time"
					) <= number(
						details,
						"captureFinished"
					) + 1)
					{
						errors.append(prefix + ": invalid post-capture state observation time")
					}
				}
			}
			if text(
				details,
				"step"
			) == "Stop streaming",
				matches("backend-trace")
				.isEmpty
			{
				errors.append(prefix + ": missing backend trace after Stop")
			}
			values.append(details)
		}
		catch
		{
			errors.append(prefix + ": invalid checkpoint evidence: " + String(describing: error))
		}
	}
	return (values, errors)
}
func backendErrors(_ run: URL) -> [String]
{
	do
	{
		let data = try String(
			contentsOf: run.appendingPathComponent("backend-trace.jsonl"),
			encoding: .utf8
		)
		let events = try data.split(separator: "\n").map
		{
			line -> Object in
			guard let event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? Object
			else
			{
				throw EvidenceError.invalid("Invalid backend event")
			}
			return event
		}
		let methods = ["turn/start", "turn/interrupt", "turn/completed"]
		let groups = methods.map
		{
			method in events.filter
			{
				text(
					$0,
					"method"
				) == method
			}
		}
		var errors = zip(
			methods,
			groups
		).filter
		{
			$0.1.count != 1
		}
		.map
		{
			$0.0 + ": expected exactly one event"
		}
		if !errors.isEmpty
		{
			return errors
		}
		let start = groups[0][0], interrupt = groups[1][0], complete = groups[2][0]
		let fixture = try object(run.appendingPathComponent("fixture.json"))
		let origin = text(
			fixture,
			"runDirectory"
		)
		guard origin.hasPrefix("/")
		else
		{
			throw EvidenceError.invalid("Fixture run directory must be absolute")
		}
		if (start["resolvedCwd"] as? String ?? text(
			start,
			"cwd"
		)) != URL(fileURLWithPath: origin)
			.appendingPathComponent("project with spaces")
			.path
		{
			errors.append("Backend received the wrong project path")
		}
		let expected: [Object] = [[
			"text": "E2E example: stream Markdown — café 日本語 so I can stop it.",
			"text_elements": [],
			"type": "text"
		]]
		if (start["input"] as? NSArray)?
			.isEqual(to: expected) !=
			true
		{
			errors.append("Backend did not receive the exact single text input")
		}
		if [start, interrupt, complete]
			.contains(where:
				{
					text(
						$0,
						"threadId"
					) != "qa-reading"
				})
		{
			errors.append("Backend events belong to the wrong thread")
		}
		if text(
			interrupt,
			"turnId"
		).isEmpty || text(
			interrupt,
			"turnId"
		) != text(
			complete,
			"turnId"
		)
		{
			errors.append("Interrupted and completed turn owners differ")
		}
		if text(
			complete,
			"status"
		) !=
			"interrupted"
		{
			errors.append("Backend completion was not interrupted")
		}
		if !(number(
			start,
			"time"
		) <= number(
			interrupt,
			"time"
		) && number(
			interrupt,
			"time"
		) <=
			number(
				complete,
				"time"
			))
		{
			errors.append("Backend event order is inconsistent")
		}
		return errors
	}
	catch
	{
		return ["Backend outcome evidence is unreadable: " + String(describing: error)]
	}
}
func visualErrors(
	_ run: URL,
	attachments: [Object],
	completed: Bool
) throws -> [String]
{
	var errors: [String] = [], results: [Object] = []
	if completed
	{
		for stage in ["streaming", "stopped"] where attachments.filter(
			{
				text(
					$0,
					"suggestedHumanReadableName"
				).contains("-" + stage + "-application_")
			}
		).count != 1
		{
			errors.append("Expected exactly one visual checkpoint: " + stage)
		}
	}
	for attachment in attachments
	{
		let name = text(
			attachment,
			"suggestedHumanReadableName"
		)
		guard ["streaming", "stopped"]
			.contains(where:
				{
					name.contains("-" + $0 + "-application_")
				})
		else
		{
			continue
		}
		do
		{
			let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
			request.usesLanguageCorrection = false; request.recognitionLanguages = ["en-US"]
			try VNImageRequestHandler(url: attachmentURL(
				run,
				attachment
			)).perform([request])
			let observations: [Object] = (request.results ?? []).compactMap
			{
				observation in
				guard let candidate = observation.topCandidates(1).first
				else
				{
					return nil
				}
				let box = observation.boundingBox
				return [
					"text": candidate.string,
					"confidence": candidate.confidence,
					"normalizedBox": [
						Double(box.minX),
						Double(box.minY),
						Double(box.width),
						Double(box.height)
					]
				]
			}
			let matches = observations
				.filter
				{
					text(
						$0,
						"text"
					).uppercased().filter
					{
						$0.isLetter || $0.isNumber
					}
					.contains("STREAMSTARTMARKER") && number(
						$0,
						"confidence"
					) >= 0.5
				}
			let readable = !matches.isEmpty
			let inside = readable && matches.allSatisfy
			{
				item in
				let box = item["normalizedBox"] as! [Double]
				return box[0] > 0.002 && box[0] + box[2] < 0.998 && box[1] > 0.002 && box[1] +
					box[3] < 0.998
			}
			results.append([
				"attachment": name,
				"markerReadable": readable,
				"markerInsideImage": inside,
				"observations": observations
			])
			if !readable ||
				!inside
			{
				errors.append("Visual marker is unreadable or clipped: " + name)
			}
		}
		catch
		{
			errors.append("Visual analysis failed: " + String(describing: error))
		}
	}
	try write(
		["results": results,
			"errors": errors,
			"scope": "OCR of the stream marker only",
			"coordinateSystem": "Normalized image coordinates, origin bottom-left"],
		run.appendingPathComponent("visual-validation.json")
	)
	return errors
}
func report(
	_ run: URL,
	exitCode: Int
) throws -> Object
{
	var errors: [String] = []
	let exportErrors = run.appendingPathComponent("export-errors.txt")
	if let value = try? String(
		contentsOf: exportErrors,
		encoding: .utf8
	)
	{
		errors += value.split(separator: "\n").map(String.init)
	}
	var attachments: [Object] = []
	do
	{
		guard let manifest = try read(run
			.appendingPathComponent("attachments/manifest.json")) as? [Object]
		else
		{
			throw EvidenceError.invalid("Invalid manifest")
		}
		for test in manifest
		{
			guard let items = test["attachments"] as? [Object]
			else
			{
				throw EvidenceError.invalid("Invalid attachment list")
			}
			attachments += items
		}
		attachments.sort
		{
			number(
				$0,
				"timestamp"
			) < number(
				$1,
				"timestamp"
			)
		}
	}
	catch
	{
		errors.append("Attachment manifest is unreadable: " + String(describing: error))
	}
	let checkpoints = attachments
		.filter
		{
			text(
				$0,
				"suggestedHumanReadableName"
			).contains("-checkpoint")
		}
	let (values, checkpointErrors) = checkpointValidation(
		run,
		attachments: attachments,
		checkpoints: checkpoints
	)
	errors += checkpointErrors
	let validation: Object = [
		"schemaVersion": 2,
		"checkpointCount": checkpoints.count,
		"checkpointErrors": checkpointErrors,
		"staleStateObservations": values.filter
		{
			$0["stateAgeSeconds"] != nil
		},
		"hasFailureCheckpoint": values.contains
		{
			!text(
				$0,
				"issue"
			).isEmpty
		},
		"hasApplicationScreenshot": attachments
			.contains
			{
				text(
					$0,
					"suggestedHumanReadableName"
				).contains("-application_")
			},
		"hasStateHistory": attachments
			.contains
			{
				text(
					$0,
					"suggestedHumanReadableName"
				).contains("-state-history")
			},
		"hasUIHierarchy": attachments
			.contains
			{
				text(
					$0,
					"suggestedHumanReadableName"
				).contains("-ui-hierarchy")
			},

	]
	try write(
		validation,
		run.appendingPathComponent("evidence-validation.json")
	)
	if checkpoints
		.isEmpty
	{
		errors.append("No custom UI checkpoints were captured; inspect Xcode diagnostics.")
	}
	for key in ["hasApplicationScreenshot", "hasStateHistory", "hasUIHierarchy"] where !bool(
		validation,
		key
	)
	{
		errors.append("Required diagnostic evidence is missing: " + key)
	}
	let summary: Object
	do
	{
		summary = try object(run.appendingPathComponent("summary.json"))
	}
	catch
	{
		summary = [:]; errors.append("Test summary is unreadable: " + String(describing: error))
	}
	let failures = summary["testFailures"] as? [Object] ?? []
	let completed = text(
		summary,
		"result"
	) == "Passed" || checkpoints.contains
	{
		text(
			$0,
			"suggestedHumanReadableName"
		).contains("-stopped-checkpoint")
	}
	if completed
	{
		let outcomeErrors = backendErrors(run); errors += outcomeErrors
		try write(
			["accepted": outcomeErrors.isEmpty, "errors": outcomeErrors],
			run.appendingPathComponent("backend-validation.json")
		)
	}
	errors += try visualErrors(
		run,
		attachments: attachments,
		completed: completed
	)
	if let value = try? String(
		contentsOf: run.appendingPathComponent("identity-errors.txt"),
		encoding: .utf8
	)
	{
		errors += value.split(separator: "\n").map(String.init)
	}
	var lines = [
		"# Streaming and Stop UI workflow",
		"",
		"Xcode command exit code: \(exitCode)",
		"",
		"Evidence: launched native app with a supplied QA backend; "
			+ "model-call behavior is not verified.",
		"",
		"Check expected/observed behavior and target frames, then application/screen images, "
			+ "UI hierarchy, state history and backend trace. Captures are sequential. "
			+ "State publications do not establish which revision was drawn. "
			+ "OCR checks only the stream marker.",
		"",
		"[Xcode log](xcodebuild.log) · [Result bundle](workflow.xcresult)",
		""
	]
	for name in [
		"summary.json",
		"tests.json",
		"fixture.json",
		"state-history.json",
		"backend-trace.jsonl",
		"app-sample.txt"
	]
		where FileManager.default
		.fileExists(atPath: run.appendingPathComponent(name).path)
	{
		lines.append("- [\(name)](\(name))")
	}
	lines += ["", "## Checkpoints", ""]
	for checkpoint in checkpoints
	{
		let prefix = text(
			checkpoint,
			"suggestedHumanReadableName"
		)
		.components(separatedBy: "-checkpoint")[0]
		do
		{
			var details = try object(attachmentURL(
				run,
				checkpoint
			))
			if let recorded = values.first(where:
				{
					number(
						$0,
						"captureStarted"
					) == number(
						details,
						"captureStarted"
					)
				}), let age = recorded["stateAgeSeconds"]
			{
				details["stateAgeSeconds"] = age
			}
			guard details["step"] is String,
					details["expected"] is String
			else
			{
				throw EvidenceError.invalid("Missing step/expectation")
			}
			let encoded = try JSONSerialization.data(
				withJSONObject: details,
				options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
			)
			lines += [
				"### \(prefix): \(text(details, "step"))",
				"",
				"Expected: " + text(
					details,
					"expected"
				),
				"",
				"Issue: " +
					(text(
						details,
						"issue"
					)
					.isEmpty ? "No assertion failure at this checkpoint" : text(
						details,
						"issue"
					)),
				"",
				"```json",
				String(
					decoding: encoded,
					as: UTF8.self
				),
				"```",
				""
			]
			for attachment in attachments
				where text(
					attachment,
					"suggestedHumanReadableName"
				).hasPrefix(prefix + "-")
			{
				let label = text(
					attachment,
					"suggestedHumanReadableName"
				),
					file = try attachmentURL(
						run,
						attachment
					)
				lines.append("- [\(label)](attachments/\(file.lastPathComponent))")
				if label.contains("-application_") || label.contains("-target_")
				{
					lines += [
						"",
						"![\(label)](\(file.path))",
						""
					]
				}
			}
		}
		catch
		{
			lines += [
				"### \(prefix): unreadable checkpoint",
				"",
				String(describing: error),
				""
			]
		}
	}
	for failure in failures
	{
		lines += ["", "Test failure: " + text(
			failure,
			"failureText"
		), ""]
	}
	lines += [
		"[Evidence validation](evidence-validation.json)",
		"[Visual validation](visual-validation.json)",
		"[Complete attachment manifest](attachments/manifest.json)"
	]
	if completed
	{
		lines.append("[Backend outcome validation](backend-validation.json)")
	}
	if !errors.isEmpty
	{
		lines += ["", "## Collection limitations", ""] + errors.map
		{
			"- " + $0
		}
	}
	try (lines.joined(separator: "\n") + "\n").write(
		to: run.appendingPathComponent("report.md"),
		atomically: true,
		encoding: .utf8
	)
	let accepted = exitCode == 0 && text(
		summary,
		"result"
	) == "Passed"
		&& integer(
			summary,
			"passedTests"
		) == 1
		&& integer(
			summary,
			"failedTests"
		) == 0 && errors.isEmpty
	let result: Object = [
		"accepted": accepted,
		"exitCode": exitCode,
		"testResult": summary["result"] ?? "Unavailable",
		"failures": failures,
		"evidenceErrors": errors,
		"report": run.appendingPathComponent("report.md").path
	]
	try write(
		result,
		run.appendingPathComponent("assessment.json")
	)
	return result
}

do
{
	let args = Array(CommandLine.arguments.dropFirst())
	guard (args.first == "report" && args.count == 3) || (args.first == "batch" && args.count == 6)
	else
	{
		throw EvidenceError.invalid("Use report <run> <exit-code> or batch <directory> "
			+ "<source-hash> <repeat> <runner-hash> <bundle-hash>")
	}
	if args[0] == "report"
	{
		let result = try report(
			URL(fileURLWithPath: args[1]),
			exitCode: Int(args[2]) ?? 1
		)
		let outcome = text(
			result,
			"testResult"
		)
		let accepted = bool(
			result,
			"accepted"
		)
		let path = text(
			result,
			"report"
		)
		print("\(outcome); evidence accepted=\(accepted); \(path)")
		exit(accepted ? 0 : 1)
	}
	else if args[0] == "batch"
	{
		let batch = URL(fileURLWithPath: args[1])
		let runs = try FileManager.default.contentsOfDirectory(
			at: batch,
			includingPropertiesForKeys: nil
		).filter
		{
			$0.lastPathComponent.hasPrefix("run-")
		}.sorted
		{
			$0.path < $1.path
		}
		let results = try runs.map
		{
			try object($0.appendingPathComponent("assessment.json"))
		}
		try write(
			["sourceFingerprint": args[2],
				"requestedRuns": Int(args[3]) ?? 1,
				"testRunnerFingerprint": args[4].isEmpty ? NSNull() : args[4] as Any,
				"bundleFingerprint": args[5],
				"results": results,
				"acceptedRuns": results.filter
				{
				bool(
					$0,
					"accepted"
				)
				}.count],
			batch.appendingPathComponent("batch-summary.json")
		)
	}
	else
	{
		throw EvidenceError.invalid("Unknown evidence command")
	}
}
catch
{
	FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8)); exit(1)
}
