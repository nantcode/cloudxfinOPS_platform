import json
import os
from datetime import datetime, timedelta, timezone

import boto3

cloudwatch = boto3.client("cloudwatch")


def handler(event, context):
    bots = json.loads(os.environ.get("HEARTBEATS", "{}"))
    now = datetime.now(timezone.utc)
    results = {}
    for function_name, minutes in bots.items():
        stats = cloudwatch.get_metric_statistics(
            Namespace="AWS/Lambda",
            MetricName="Invocations",
            Dimensions=[{"Name": "FunctionName", "Value": function_name}],
            StartTime=now - timedelta(minutes=int(minutes)),
            EndTime=now,
            Period=60,
            Statistics=["Sum"],
        )
        runs = sum(point["Sum"] for point in stats["Datapoints"])
        quiet = 0 if runs > 0 else 1
        results[function_name] = {"runs": runs, "quiet": quiet}
        cloudwatch.put_metric_data(
            Namespace="Fleet/Heartbeat",
            MetricData=[{
                "MetricName": "Quiet",
                "Dimensions": [{"Name": "FunctionName", "Value": function_name}],
                "Value": quiet,
                "Unit": "Count",
            }],
        )
    print(json.dumps(results))
    return results
