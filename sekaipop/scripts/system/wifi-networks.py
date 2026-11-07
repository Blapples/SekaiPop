#!/usr/bin/env python3
"""Read visible Wi-Fi networks and matching saved profile UUIDs; never read secrets."""
import json
import os
import subprocess
import sys
import time


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


def security_kind(security):
    if security in ("", "--"):
        return "open"
    return "enterprise" if "802.1X" in security else "personal"


def saved_profiles():
    profiles = {}
    # Profile names need not equal their SSIDs. Only UUIDs are used for activation.
    for line in nmcli("-t", "-f", "UUID,TYPE,ACTIVE", "connection", "show").splitlines():
        uuid, kind, active = fields(line)
        if kind not in ("802-11-wireless", "wifi"):
            continue
        try:
            detail = nmcli("-t", "-e", "no", "-g",
                           "802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless.mode",
                           "connection", "show", "uuid", uuid).splitlines()
        except RuntimeError:
            # A profile can disappear between enumeration and inspection.
            continue
        if len(detail) < 3 or detail[2] == "ap":
            continue
        ssid, key_mgmt = detail[:2]
        if not ssid:
            continue
        security = ("open" if key_mgmt in ("", "--") else
                    "enterprise" if key_mgmt in ("wpa-eap", "wpa-eap-suite-b-192", "ieee8021x") else
                    "personal")
        key = (ssid, security)
        if key not in profiles or active == "yes":
            profiles[key] = uuid
    return profiles


def networks(rescan=False):
    if rescan:
        try:
            nmcli("device", "wifi", "rescan", timeout=5)
        except (RuntimeError, subprocess.TimeoutExpired):
            pass
        time.sleep(2)
    profiles = saved_profiles()
    rows = {}
    listing = nmcli("-t", "-e", "yes", "-f", "SSID,SIGNAL,SECURITY,IN-USE",
                    "device", "wifi", "list", "--rescan", "no")
    for line in listing.splitlines():
        values = fields(line)
        if len(values) != 4:
            continue
        ssid, signal, security, in_use = values
        if not ssid:
            continue
        row = {"ssid": ssid, "signal": int(signal or 0),
               "secured": security_kind(security) != "open", "connected": in_use == "*",
               "profileUuid": profiles.get((ssid, security_kind(security)), "")}
        old = rows.get(ssid)
        # Preserve a connected BSSID even when another AP has a stronger signal.
        if old is None or (row["connected"], row["signal"]) > (old["connected"], old["signal"]):
            rows[ssid] = row
    return sorted(rows.values(), key=lambda row: (not row["connected"], -row["signal"]))


if __name__ == "__main__":
    try:
        print(json.dumps(networks("--rescan" in sys.argv[1:]), ensure_ascii=False))
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
