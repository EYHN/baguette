#!/usr/bin/env python3
"""Display & Text Size — read and change the settings an audit runs against.

The audit next door reports what a screen-reader user would hit. This
one changes the conditions the screen is rendered under, so you can
re-run that audit in dark mode, with Increase Contrast on, or at an
accessibility text size — which is where layouts actually break.

Every row is a `rowAction: "run"` row: clicking one calls back into this
same command with `args`, which applies the change and prints the fresh
state. The panel re-renders from that answer, so what you see is what
the device reports, not what the click assumed.

  in   BAGUETTE_URL / BAGUETTE_UDID / BAGUETTE_TOKEN in the environment,
       plus the clicked row's `args` in the JSON on stdin
  out  one JSON object on stdout: {"ok": bool, "message"?, "rows": [...]}
"""

import json
import os
import sys
import urllib.error
import urllib.request

# The five "Larger Accessibility Sizes" plus the default, which is where
# most testing starts. The full twelve are available over the API; a
# panel listing all of them would be a scroll, not a control.
OFFERED_SIZES = [
    ("large", "Default"),
    ("extra-extra-extra-large", "Largest standard"),
    ("accessibility-medium", "Accessibility M"),
    ("accessibility-large", "Accessibility L"),
    ("accessibility-extra-extra-extra-large", "Accessibility XXXL"),
]


def answer(ok, rows=None, message=None):
    out = {"ok": ok, "rows": rows or []}
    if message:
        out["message"] = message
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")
    sys.exit(0)


def call(method, path, token, body=None):
    """One request against the running server. Raises on failure."""
    data = json.dumps(body).encode() if body is not None else None
    headers = {"X-Baguette-Token": token}
    if data:
        headers["content-type"] = "application/json"
    request = urllib.request.Request(path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=8) as response:
        return json.load(response)


def picked_row(title, subtitle, selected, args):
    """A choice. The selected one is marked and carries no action —
    re-applying what's already set would spawn simctl to change nothing."""
    row = {
        "title": ("● " if selected else "○ ") + title,
        "subtitle": subtitle,
        "severity": "info",
    }
    if not selected:
        row["run"] = "display"
        row["args"] = args
    return row


def rows_for(state):
    appearance = state.get("appearance")
    contrast = state.get("increaseContrast")
    size = state.get("contentSize")

    rows = [{"title": "Appearance", "severity": "info"}]
    for value, label in (("light", "Light"), ("dark", "Dark")):
        rows.append(picked_row(
            label, None, appearance == value, {"appearance": value}
        ))

    rows.append({"title": "Increase Contrast", "severity": "info"})
    for value, label in (("disabled", "Off"), ("enabled", "On")):
        rows.append(picked_row(
            label, None, contrast == value, {"increaseContrast": value}
        ))

    rows.append({"title": "Text size", "severity": "info"})
    for value, label in OFFERED_SIZES:
        rows.append(picked_row(
            label,
            value if value != size else f"{value} — current",
            size == value,
            {"contentSize": value},
        ))
    # A size outside the offered set is still reachable by stepping, and
    # the current one is always named above.
    rows.append(picked_row("Smaller", "one step down", False, {"contentSize": "decrement"}))
    rows.append(picked_row("Larger", "one step up", False, {"contentSize": "increment"}))
    return rows


def main():
    base = os.environ.get("BAGUETTE_URL")
    udid = os.environ.get("BAGUETTE_UDID")
    token = os.environ.get("BAGUETTE_TOKEN", "")
    if not base or not udid:
        answer(False, message="No device focused")

    # The clicked row's args, when a row was clicked. Opening the panel
    # sends none, which means "just show me the current state".
    try:
        context = json.load(sys.stdin)
    except Exception:  # noqa: BLE001 - stdin is optional
        context = {}
    args = context.get("args") or {}

    url = f"{base}/simulators/{udid}/interface"
    try:
        if args:
            state = call("POST", url, token, body=args)
        else:
            state = call("GET", url + ".json", token)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        answer(False, message=f"Could not reach the interface settings: {detail}")
    except Exception as error:  # noqa: BLE001 - surfaced to the user verbatim
        answer(False, message=f"Could not reach the interface settings: {error}")

    # A device that isn't booted answers "unknown" for all three. Say so
    # rather than drawing a picker whose every option looks unselected.
    if state.get("appearance") in (None, "unknown", "unsupported"):
        answer(True, rows=[{
            "title": "Boot the device to change these",
            "subtitle": "appearance, contrast and text size need a running simulator",
            "severity": "warn",
        }])

    answer(True, rows=rows_for(state))


if __name__ == "__main__":
    main()
