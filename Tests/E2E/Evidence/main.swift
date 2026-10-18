import Foundation
import ImageIO
import Vision

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
