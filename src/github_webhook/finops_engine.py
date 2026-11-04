import json
import re

PROHIBITED_INSTANCE_TYPES = ["m5.xlarge", "m5.2xlarge", "c5.4xlarge", "i3.metal"]
ALLOWED_ENV_TAGS = ["dev", "staging", "prod"]

class FinOpsPolicyEngine:
    def __init__(self, plan_or_files):
        self.input_data = plan_or_files
        self.violations = []
        self.warnings = []

    def evaluate(self):
        # Handle list of file objects from GitHub API [{ 'filename': '...', 'patch': '...' }]
        if isinstance(self.input_data, list):
            for file_item in self.input_data:
                patch = file_item.get('patch', '') or ''
                filename = file_item.get('filename', 'unknown.tf')

                for inst in PROHIBITED_INSTANCE_TYPES:
                    if re.search(rf'instance_type\s*=\s*["\']{inst}["\']', patch) or \
                       re.search(rf'instance_class\s*=\s*["\']{inst}["\']', patch):
                        self.violations.append(
                            f"⛔ **[Cost Violation]** `{filename}` uses prohibited instance type `{inst}`."
                        )

        # Handle Terraform JSON plan dictionary
        elif isinstance(self.input_data, dict):
            resource_changes = self.input_data.get("resource_changes", [])
            for resource in resource_changes:
                actions = resource.get("change", {}).get("actions", [])
                if "create" not in actions and "update" not in actions:
                    continue

                res_type = resource.get("type")
                res_name = resource.get("name")
                after_values = resource.get("change", {}).get("after", {}) or {}

                if res_type in ["aws_instance", "aws_db_instance"]:
                    instance_type = after_values.get("instance_type") or after_values.get("instance_class")
                    if instance_type in PROHIBITED_INSTANCE_TYPES:
                        self.violations.append(
                            f"⛔ **[Cost Violation]** `{res_type}.{res_name}` uses oversized instance type `{instance_type}`."
                        )

        return {
            "passed": len(self.violations) == 0,
            "violations": self.violations,
            "warnings": self.warnings
        }