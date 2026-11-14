#!/usr/bin/env python3
"""Generates singbox/zapret-domains.json (remote rule-set) from the upstream
Flowseal lists and singbox/profile.json (remote profile that references it).
Mirrors Shared/SingBoxProfile.swift."""
import json
import os
import sys
import urllib.request

UPSTREAM = "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists/"
LISTS = ["list-general.txt", "list-google.txt"]
OWNER, REPO = "absolute2007", "zapret-ios"
RULESET_URL = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/main/singbox/zapret-domains.json"


def entries(text):
    out = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip().lstrip("^").lower()
        if line and " " not in line and "." in line and "/" not in line:
            out.append(line)
    return out


def main(out_dir="singbox", local_lists=None):
    domains = set()
    for name in LISTS:
        if local_lists:
            with open(os.path.join(local_lists, name), encoding="utf-8") as f:
                text = f.read()
        else:
            with urllib.request.urlopen(UPSTREAM + name, timeout=30) as r:
                text = r.read().decode("utf-8")
        items = entries(text)
        if not items:
            print(f"{name}: empty, refusing to continue", file=sys.stderr)
            return 1
        domains.update(items)

    os.makedirs(out_dir, exist_ok=True)
    ruleset = {"version": 2, "rules": [{"domain_suffix": sorted(domains)}]}
    profile = {
        "log": {"level": "warn"},
        "dns": {
            "servers": [{"type": "https", "tag": "remote", "server": "1.1.1.1"}],
            "final": "remote",
            "strategy": "prefer_ipv4",
        },
        "inbounds": [{
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
            "auto_route": True,
            "strict_route": True,
        }],
        "outbounds": [
            {"type": "direct", "tag": "direct"},
            {"type": "socks", "tag": "zapret", "server": "127.0.0.1", "server_port": 1080, "version": "5"},
        ],
        "route": {
            "rules": [
                {"action": "sniff"},
                {"protocol": "dns", "action": "hijack-dns"},
                {"ip_is_private": True, "outbound": "direct"},
                {"rule_set": ["zapret-domains"], "outbound": "zapret"},
                {"network": "udp", "port_range": ["50000:50100", "19294:19344"], "outbound": "zapret"},
            ],
            "rule_set": [{
                "type": "remote",
                "tag": "zapret-domains",
                "format": "source",
                "url": RULESET_URL,
                "download_detour": "direct",
                "update_interval": "24h",
            }],
            "final": "direct",
            "auto_detect_interface": True,
        },
    }
    for name, data in (("zapret-domains.json", ruleset), ("profile.json", profile)):
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
    print(f"{len(domains)} domains")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
