import Foundation

/// Copies mutable Foundation containers into value types before asynchronous serialization.
indirect enum ProtocolJSONValue: Sendable
{
	case null
	case number(NSNumber)
	case string(String)
	case array([ProtocolJSONValue])
	case object([String: ProtocolJSONValue])

	init(snapshot value: Any) throws
	{
		switch value
		{
		case is NSNull:
			self = .null
		case let number as NSNumber:
			self = .number(number.copy() as! NSNumber)
		case let string as String:
			self = .string(string)
		case let array as [Any]:
			self = .array(try array.map
			{
				try ProtocolJSONValue(snapshot: $0)
			})
		case let object as [String: Any]:
			self = .object(try object.mapValues
			{
				try ProtocolJSONValue(snapshot: $0)
			})
		default:
			throw AppServerError
				.protocolError("An app-server message contains an invalid JSON value.")
		}
	}

	var foundationValue: Any
	{
		switch self
		{
		case .null: NSNull()
		case .number(let value): value
		case .string(let value): value
		case .array(let values): values.map(\.foundationValue)
		case .object(let values): values.mapValues(\.foundationValue)
		}
	}
}
