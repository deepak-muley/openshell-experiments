#!/usr/bin/env python3
"""Probe agent for an OpenShell sandbox.

This process is the stand-in for a harness. It does not call a model.
It checks the two boundaries OpenShell is here to enforce:

- filesystem: writes under /sandbox succeed, writes under /etc do not
- network: curl may GET https://example.com and may not reach anything else

The sandbox policy in policies/sample-agent.yaml is what makes those
outcomes true. Running this file on your laptop will not reproduce them.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

os.environ.setdefault("HOME", "/tmp")
os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")

REPORT = Path("/sandbox/report.json")
ALLOWED_URL = "https://example.com/"
DENIED_URL = "https://example.org/"


def record(rows: list[dict], name: str, ok: bool, detail: str) -> None:
    rows.append({"check": name, "ok": ok, "detail": detail})
    mark = "PASS" if ok else "FAIL"
    print(f"{mark} {name}: {detail}", flush=True)


def curl(url: str) -> tuple[int, str]:
    completed = subprocess.run(
        [
            "/usr/bin/curl",
            "-fsS",
            "--max-time",
            "25",
            "-o",
            "/tmp/openshell-probe-body",
            "-w",
            "%{http_code}",
            url,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    detail = (completed.stderr or completed.stdout or "").strip().replace("\n", " ")
    return completed.returncode, detail[-400:]


def main() -> int:
    rows: list[dict] = []

    hello = Path("/sandbox/hello.txt")
    try:
        hello.write_text("hello from the openshell sandbox\n", encoding="utf-8")
        record(rows, "write_/sandbox", True, f"wrote {hello}")
    except OSError as exc:
        record(rows, "write_/sandbox", False, f"{type(exc).__name__}: {exc}")

    secret = Path("/etc/openshell-probe")
    try:
        secret.write_text("this should not land on disk\n", encoding="utf-8")
    except OSError as exc:
        record(rows, "deny_write_/etc", True, f"{type(exc).__name__}: {exc}")
    else:
        secret.unlink(missing_ok=True)
        record(
            rows,
            "deny_write_/etc",
            False,
            "LANDLOCK_UNAVAILABLE write to /etc succeeded; kernel has no Landlock",
        )

    code, detail = curl(ALLOWED_URL)
    record(
        rows,
        "allow_example.com",
        code == 0,
        f"curl exit {code}; {detail or 'no stderr'}",
    )

    code, detail = curl(DENIED_URL)
    record(
        rows,
        "deny_example.org",
        code != 0,
        f"curl exit {code}; {detail or 'no stderr'}",
    )

    try:
        REPORT.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        print(f"FAIL write_report: {exc}", flush=True)

    by_name = {row["check"]: row["ok"] for row in rows}
    network_ok = by_name.get("allow_example.com") and by_name.get("deny_example.org")
    workspace_ok = by_name.get("write_/sandbox", False)
    landlock_ok = by_name.get("deny_write_/etc", False)
    if network_ok and workspace_ok and landlock_ok:
        result = "pass"
    elif network_ok and workspace_ok:
        result = "pass"
        print(
            "INFO filesystem Landlock is not enforced on this kernel. "
            "Network allow and deny are the sandbox boundary that held.",
            flush=True,
        )
    else:
        result = "fail"
    print(f"SAMPLE_AGENT_RESULT={result}", flush=True)
    return 0 if result == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
