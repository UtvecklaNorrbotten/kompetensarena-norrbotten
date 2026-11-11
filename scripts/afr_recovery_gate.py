"""Gate the 08:15 Europe/Stockholm AFR retry using GitHub Actions history."""
import json
import os
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

STOCKHOLM = ZoneInfo("Europe/Stockholm")
RECOVERY_CRONS = {"15 6 * * *": 6, "15 7 * * *": 7}


def is_recovery_slot(cron, utc_date):
    hour = RECOVERY_CRONS.get(cron)
    if hour is None:
        return False
    slot = datetime(utc_date.year, utc_date.month, utc_date.day, hour, 15, tzinfo=timezone.utc)
    return slot.astimezone(STOCKHOLM).hour == 8


def had_successful_run(runs, local_day, current_id):
    for run in runs:
        if str(run.get("id")) == str(current_id) or run.get("conclusion") != "success":
            continue
        created = run.get("created_at")
        if not created:
            continue
        at = datetime.fromisoformat(created.replace("Z", "+00:00")).astimezone(STOCKHOLM)
        # Exclude 07:15 local: that is the inactive daylight-saving cron.
        if at.date() == local_day and at.hour in (4, 5, 6, 8):
            return True
    return False


def fetch_runs(repository, token):
    url = f"https://api.github.com/repos/{repository}/actions/workflows/etl-scb-afr-daily.yml/runs?event=schedule&per_page=100"
    req = Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with urlopen(req, timeout=20) as response:
        return json.load(response).get("workflow_runs", [])


def should_recover(cron, now, runs, current_id):
    if not is_recovery_slot(cron, now.date()):
        return False
    return not had_successful_run(runs, now.astimezone(STOCKHOLM).date(), current_id)


def main():
    cron = os.environ.get("GITHUB_EVENT_SCHEDULE", "")
    now = datetime.now(timezone.utc)
    enabled = False
    if is_recovery_slot(cron, now.date()):
        try:
            runs = fetch_runs(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
            enabled = should_recover(cron, now, runs, os.environ.get("GITHUB_RUN_ID", ""))
        except (OSError, ValueError, KeyError) as exc:
            # Fail open: AFR compares source dates and does not republish unchanged data.
            print(f"Could not inspect previous runs ({exc}); check AFR anyway.")
            enabled = True
    print("08:15 AFR recovery:", "run" if enabled else "skip")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
        f.write(f"should_run={'true' if enabled else 'false'}\n")


if __name__ == "__main__":
    main()
