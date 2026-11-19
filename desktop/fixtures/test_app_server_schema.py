from unittest import TestCase

from check_app_server_schema import SchemaMismatch, check_fields


class SchemaContractTests(TestCase):
    def test_detects_missing_incoming_identity_field(self):
        schema = {"properties": {"itemId": {"type": "string"}}}
        with self.assertRaisesRegex(SchemaMismatch, "missing fields threadId"):
            check_fields(schema, ("itemId", "threadId"), "server approval")

    def test_detects_a_new_required_outgoing_field(self):
        schema = {
            "properties": {"decision": {"type": "string"}, "scope": {"type": "string"}},
            "required": ["decision", "scope"],
        }
        check_fields(schema, ("decision", "scope"), "approval reply", outbound=True)
        with self.assertRaisesRegex(SchemaMismatch, "additional required fields scope"):
            check_fields(schema, ("decision",), "approval reply", outbound=True)
