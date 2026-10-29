# Turns raw cisco.ios resource data (state gathered / parsed) into the
# host_vars/<switch>/ios_resources.yml format, so the conversion is versioned
# and reproducible instead of done by hand.

import re

# Defaults IOS hides in the running config. With state replaced, cisco.ios
# sends "no ip redirects" (and the others) when the option is absent on both
# sides, so they are written explicitly on every L3 interface.
L3_DEFAULT_FLAGS = ("redirects", "unreachables", "ipv6_redirects", "ipv6_unreachables")


def _natural_key(entry):
    name = entry.get("name", "") if isinstance(entry, dict) else ""
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", name)]


def _has_config(entry, default_keys):
    """True when the entry carries more than its name and default values."""
    for key, value in entry.items():
        if key == "name":
            continue
        if key not in default_keys or (key == "enabled" and value is not True):
            return True
    return False


def ios_resources_prune(raw):
    """Raw resources -> ios_resources: drop defaults, sort ports, explicit L3 flags."""
    raw = raw or {}
    out = {}
    # VLAN 1 and 1002-1005 are built in and cannot be configured.
    out["vlans"] = [v for v in raw.get("vlans") or [] if 1 < v["vlan_id"] < 1002]
    out["interfaces"] = [e for e in raw.get("interfaces") or [] if _has_config(e, {"enabled"})]
    for key in ("l2_interfaces", "l3_interfaces", "lacp_interfaces"):
        out[key] = [e for e in raw.get(key) or [] if _has_config(e, set())]
    for key in ("lag_interfaces", "acls", "acl_interfaces", "static_routes"):
        out[key] = raw.get(key) or []
    for entry in out["l3_interfaces"]:
        for flag in L3_DEFAULT_FLAGS:
            entry.setdefault(flag, True)
    for value in out.values():
        if value and isinstance(value[0], dict) and "name" in value[0]:
            value.sort(key=_natural_key)
    return {key: value for key, value in out.items() if value}


def ios_vlans_from_config(running_config):
    """VLANs from a running config (VTP transparent), for IOS where ios_vlans
    cannot parse offline: it still tries to reach the device."""
    return [
        {"vlan_id": int(vlan_id), "name": name, "state": "active", "shutdown": "disabled"}
        for vlan_id, name in re.findall(r"^vlan (\d+)\n name (\S+)", running_config, re.M)
    ]


class FilterModule:
    def filters(self):
        return {
            "ios_resources_prune": ios_resources_prune,
            "ios_vlans_from_config": ios_vlans_from_config,
        }
