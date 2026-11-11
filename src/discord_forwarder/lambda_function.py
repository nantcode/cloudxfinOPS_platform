import json
import os
import urllib.request

import boto3

ssm = boto3.client("ssm")
WEBHOOK_URL = None


def get_webhook_url():
    global WEBHOOK_URL
    if not WEBHOOK_URL:
        name = os.environ.get("DISCORD_WEBHOOK_PARAM", "/fleet/discord_webhook_url")
        WEBHOOK_URL = ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
    return WEBHOOK_URL


def format_message(sns):
    try:
        alarm = json.loads(sns.get("Message", ""))
    except ValueError:
        alarm = None
    if isinstance(alarm, dict) and "AlarmName" in alarm:
        state = alarm.get("NewStateValue", "UNKNOWN")
        icon = {"ALARM": "\U0001F534", "OK": "\U0001F7E2"}.get(state, "\u26AA")
        reason = alarm.get("NewStateReason", "")[:500]
        return f"{icon} **{alarm['AlarmName']}** is {state}\n{reason}"
    subject = sns.get("Subject") or "Fleet alert"
    return f"**{subject}**\n{sns.get('Message', '')[:1500]}"


def handler(event, context):
    url = get_webhook_url()
    for record in event.get("Records", []):
        content = format_message(record.get("Sns", {}))[:1900]
        req = urllib.request.Request(
            url,
            data=json.dumps({"content": content}).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "User-Agent": "fleet-alerts (https://github.com/nantcode/cloudxfinOPS_platform, 1.0)",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"Discord responded {resp.status}")
    return {"forwarded": len(event.get("Records", []))}
