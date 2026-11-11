import json
import os
import platform

VERSION = "1"


def handler(event, context):
    result = {
        "status": "ok",
        "bot": "fleet-canary-bot",
        "mode": os.environ.get("MODE", "paper"),
        "version": VERSION,
        "python": platform.python_version(),
    }
    print(json.dumps(result))
    return result
