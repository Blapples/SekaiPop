#!/usr/bin/env python3
"""Read saved Wi-Fi profile metadata without requesting secrets."""
import json
import os
import subprocess
import sys


def nmcli(*args, timeout=10):
    result = subprocess.run(
        ["nmcli", *args], capture_output=True, text=True,
        env={**os.environ, "LC_ALL": "C"}, timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "NetworkManager query failed")
    return result.stdout


def fields(line):
    """Split nmcli terse output, respecting escaped colons and backslashes."""
    out, current, escaped = [], [], False
    for char in line:
        if escaped:
            current.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            out.append("".join(current))
            current = []
        else:
            current.append(char)
    if escaped:
        current.append("\\")
    out.append("".join(current))
    return out


def saved_profiles():
    profiles = []
    # Profile names need not equal their SSIDs. Only UUIDs are used for activation.
    for line in nmcli("-t", "-f", "UUID,TYPE,ACTIVE", "connection", "show").splitlines():
        values = fields(line)
        if len(values) != 3:
            continue
        uuid, kind, active = values
        if kind not in ("802-11-wireless", "wifi"):
            continue
        try:
            detail = nmcli("-t", "-e", "no", "-g",
                           "802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless.mode",
                           "connection", "show", "uuid", uuid).splitlines()
        except RuntimeError:
            # A profile can disappear between enumeration and inspection.
            continue
        if len(detail) < 3 or detail[2] not in ("", "--", "infrastructure"):
            continue
        ssid, key_mgmt = detail[:2]
        if not ssid:
            continue
        security = ("open" if key_mgmt in ("", "--") else
                    "enterprise" if key_mgmt in ("wpa-eap", "wpa-eap-suite-b-192", "ieee8021x") else
                    "personal")
        profiles.append({"ssid": ssid, "securityKind": security,
                         "uuid": uuid, "active": active == "yes"})
    return profiles


if __name__ == "__main__":
    try:
        print(json.dumps(saved_profiles()))
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
