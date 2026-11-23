"""Checks for ticket 5: the heartbeat checker has to get through its whole list.

Run from the top folder of the repo:

    cd ~/projects/cloudxfinOPS_platform
    python3 -m unittest discover -s tests -p "test_heartbeat_checker.py"

You want `Ran 4 tests` and `OK`.

Nothing here talks to AWS. CloudWatch is replaced by a stand-in that follows the same rule
the real one enforced on November 18, 2026: one request may ask for at most 1,440 readings.
"""
import contextlib
import importlib.util
import io
import json
import math
import os
import sys
import traceback
import types
import unittest
from datetime import timedelta

__unittest = True       # keeps this checker's own line numbers out of the messages you see

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKER = os.path.join(REPO, "src", "heartbeat_checker", "lambda_function.py")
SHORT = "src/heartbeat_checker/lambda_function.py"
LIMIT = 1440

# The list that is live today (see `heartbeats` in main.tf), in the order the checker gets it.
# The number is the bot's window: how many minutes it may go without running.
FLEET = {"nant-trading-bot": 30, "nant-trend-bot": 4380, "nant-watch-daily": 180}

# Two slower bots you might add one day: one that runs weekly, one that runs monthly.
BIGGER_FLEET = dict(FLEET, **{"weekly-bot": 10140, "monthly-bot": 44700})


class TooManyReadings(Exception):
    """What the real CloudWatch answers when one request asks for too much."""


class StandInCloudWatch:
    """Behaves like the two CloudWatch calls the checker uses, without touching AWS."""

    def __init__(self, minutes_since_last_run):
        self.minutes_since_last_run = minutes_since_last_run    # bot -> minutes ago, or None for never
        self.asking_about = None
        self.requests = []                                      # (bot, how many readings it asked for)
        self.written = {}                                       # bot -> the quiet value the checker wrote

    def get_metric_statistics(self, Namespace, MetricName, Dimensions, StartTime, EndTime, Period, Statistics, **more):
        bot = Dimensions[0]["Value"]
        self.asking_about = bot
        if isinstance(Period, bool) or not isinstance(Period, int) or Period < 60 or Period % 60:
            raise ValueError("Period has to be a whole number of seconds and a multiple of 60. It was %r." % (Period,))
        asked = math.ceil((EndTime - StartTime).total_seconds() / Period)
        self.requests.append((bot, asked))
        if asked > LIMIT:
            raise TooManyReadings(
                "You have requested up to %d datapoints, which exceeds the limit of %d. "
                "You may reduce the datapoints requested by increasing Period, or decreasing the time range."
                % (asked, LIMIT))
        ago = self.minutes_since_last_run.get(bot)
        if ago is None:
            return {"Datapoints": []}
        ran_at = EndTime - timedelta(minutes=ago)
        if StartTime <= ran_at < EndTime:
            return {"Datapoints": [{"Timestamp": StartTime, "Sum": 1.0, "Unit": "Count"}]}
        return {"Datapoints": []}

    def put_metric_data(self, Namespace, MetricData, **more):
        for item in MetricData:
            self.written[item["Dimensions"][0]["Value"]] = item["Value"]


def run_checker(fleet, minutes_since_last_run):
    """Run your handler once against the stand-in. Gives back (the stand-in, the error or None)."""
    cloudwatch = StandInCloudWatch(minutes_since_last_run)
    pretend_boto3 = types.ModuleType("boto3")
    pretend_boto3.client = lambda *args, **kwargs: cloudwatch
    real_boto3 = sys.modules.get("boto3")
    before = os.environ.get("HEARTBEATS")
    sys.modules["boto3"] = pretend_boto3
    os.environ["HEARTBEATS"] = json.dumps(fleet)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            spec = importlib.util.spec_from_file_location("heartbeat_checker_under_test", CHECKER)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            module.handler({}, None)
    except Exception as error:
        return cloudwatch, error
    finally:
        if real_boto3 is None:
            sys.modules.pop("boto3", None)
        else:
            sys.modules["boto3"] = real_boto3
        if before is None:
            os.environ.pop("HEARTBEATS", None)
        else:
            os.environ["HEARTBEATS"] = before
    return cloudwatch, None


def line_of(error):
    """The line of your file where the error happened, or None."""
    if isinstance(error, SyntaxError):
        return error.lineno
    lines = [frame.lineno for frame in traceback.extract_tb(error.__traceback__)
             if os.path.basename(frame.filename) == "lambda_function.py"]
    return lines[-1] if lines else None


def explain_stop(fleet, cloudwatch, error):
    """Plain words for 'the checker stopped before the end of its list'."""
    where = line_of(error)
    where = "line %s of %s" % (where, SHORT) if where else SHORT
    if not isinstance(error, TooManyReadings):
        said = traceback.format_exception_only(type(error), error)[-1].strip()
        return ("\n\nThe checker stopped with an error.\nPython said:\n\n    %s\n\nLook at %s.\n"
                "The first word is the kind of error. If you just edited that line, compare it with the lines around it.\n"
                % (said, where))
    bot = cloudwatch.asking_about
    names = list(fleet)
    checked = [name for name in names if name in cloudwatch.written]
    never = [name for name in names if name not in cloudwatch.written and name != bot]
    return ("\n\nThe checker stopped part-way through its list. This is the failure from November 18.\n\n"
            "It was asking about:    %s   (window: %s minutes)\n"
            "CloudWatch refused:     %s\n"
            "The request is made on: %s\n\n"
            "Checked before it stopped:   %s\n"
            "Never reached:               %s\n"
            % (bot, fleet[bot], error, where, ", ".join(checked) or "(none)", ", ".join(never) or "(none)"))


RAN_JUST_NOW = {"nant-trading-bot": 5, "nant-trend-bot": 5, "nant-watch-daily": 5, "weekly-bot": 5, "monthly-bot": 5}


class TestHeartbeatChecker(unittest.TestCase):

    def need_a_clean_run(self, with_every_reading=False):
        cloudwatch, error = run_checker(FLEET, RAN_JUST_NOW)
        if error is not None:
            self.skipTest("get check 1 passing first")
        if with_every_reading and any(bot not in cloudwatch.written for bot in FLEET):
            self.skipTest("get check 2 passing first")

    def test_1_it_gets_through_the_whole_list(self):
        cloudwatch, error = run_checker(FLEET, RAN_JUST_NOW)
        if error is not None:
            self.fail(explain_stop(FLEET, cloudwatch, error))

    def test_2_every_bot_gets_a_reading(self):
        self.need_a_clean_run()
        cloudwatch, _ = run_checker(FLEET, RAN_JUST_NOW)
        missing = [bot for bot in FLEET if bot not in cloudwatch.written]
        if missing:
            self.fail("\n\nThe checker finished, but it wrote no reading for: %s\n"
                      "Every bot in the list needs its own `put_metric_data` call, once per turn of the loop.\n"
                      % ", ".join(missing))

    def test_3_quiet_means_no_run_inside_the_bots_own_window(self):
        self.need_a_clean_run(with_every_reading=True)
        # (bot, minutes since its last run, the quiet value that is right, why)
        cases = [
            ("nant-trading-bot", 10, 0, "it ran 10 minutes ago and its window is 30 minutes"),
            ("nant-trading-bot", 45, 1, "it last ran 45 minutes ago and its window is 30 minutes"),
            ("nant-watch-daily", 100, 0, "it ran 100 minutes ago and its window is 180 minutes"),
            ("nant-watch-daily", 200, 1, "it last ran 200 minutes ago and its window is 180 minutes"),
            ("nant-trend-bot", 4320, 0, "it ran 4,320 minutes ago (Friday 10:00 to Monday 10:00) and its window is 4,380 minutes"),
            ("nant-trend-bot", 4500, 1, "it last ran 4,500 minutes ago and its window is 4,380 minutes"),
            ("nant-trend-bot", None, 1, "it has never run"),
        ]
        for bot, ago, right, why in cases:
            last_runs = dict(RAN_JUST_NOW)
            last_runs[bot] = ago
            cloudwatch, error = run_checker(FLEET, last_runs)
            if error is not None:
                self.fail(explain_stop(FLEET, cloudwatch, error))
            mine = cloudwatch.written.get(bot)
            if mine != right:
                word = {0: "NOT quiet (0)", 1: "quiet (1)"}
                extra = ""
                if right == 0:
                    extra = ("\nDid the fix shorten the time range? The window has to stay as long as main.tf says,\n"
                             "or a healthy bot gets reported as missing.\n")
                self.fail("\n\n%s should be %s, because %s.\nYour checker wrote: %r\n%s"
                          % (bot, word[right], why, mine, extra))

    def test_4_a_slower_bot_later_will_not_break_it_again(self):
        self.need_a_clean_run(with_every_reading=True)
        cloudwatch, error = run_checker(BIGGER_FLEET, RAN_JUST_NOW)
        if isinstance(error, TooManyReadings):
            bot = cloudwatch.asking_about
            self.fail("\n\nThe fix works for today's three bots, but a slower bot would bring the same failure back.\n\n"
                      "A bot with a window of %s minutes (%s) made the checker ask for too much:\n"
                      "    %s\n\n"
                      "Make the request fit whatever window a bot has, not just the three windows in the list today.\n"
                      % (BIGGER_FLEET[bot], bot, error))
        if error is not None:
            self.fail(explain_stop(BIGGER_FLEET, cloudwatch, error))
        worst = max(asked for _, asked in cloudwatch.requests)
        self.assertLessEqual(worst, LIMIT)
        missing = [bot for bot in BIGGER_FLEET if bot not in cloudwatch.written]
        if missing:
            self.fail("\n\nWith two slower bots added, the checker wrote no reading for: %s\n" % ", ".join(missing))


if __name__ == "__main__":
    unittest.main()
