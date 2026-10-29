# Turns a pfSense config.xml into the host_vars/<firewall>/pfsense_resources.yml
# format (pfsensible.core pfsense_aggregate), so the conversion is versioned
# and reproducible.

import xml.etree.ElementTree as ET

# config.xml keywords for interface addresses -> pfsensible syntax.
_SPECIAL_NETWORKS = {"(self)": "(self)"}


def _address(endpoint):
    """<source>/<destination> -> [!]{any,(self),IP:if,NET:if,alias,ip} ."""
    if endpoint is None:
        return "any", None
    prefix = "!" if endpoint.find("not") is not None else ""
    if endpoint.find("any") is not None:
        value = "any"
    elif endpoint.findtext("address"):
        value = endpoint.findtext("address")
    else:
        network = endpoint.findtext("network") or ""
        if network in _SPECIAL_NETWORKS:
            value = _SPECIAL_NETWORKS[network]
        elif network.endswith("ip"):
            value = "IP:" + network[:-2]
        else:
            value = "NET:" + network
    return prefix + value, endpoint.findtext("port")


def pfsense_resources_from_config(config_xml):
    root = ET.fromstring(config_xml)
    aliases = []
    for alias in root.findall("./aliases/alias"):
        aliases.append({
            "name": alias.findtext("name"),
            "type": alias.findtext("type"),
            "address": alias.findtext("address") or "",
            "descr": alias.findtext("descr") or "",
            "detail": alias.findtext("detail") or "",
        })

    rules = []
    for rule in root.findall("./filter/rule"):
        # Rules created by a NAT port forward live and die with it: modelled
        # with the NAT, not here.
        if rule.findtext("associated-rule-id"):
            continue
        source, source_port = _address(rule.find("source"))
        destination, destination_port = _address(rule.find("destination"))
        entry = {
            "name": rule.findtext("descr"),
            "interface": rule.findtext("interface"),
            "action": rule.findtext("type"),
            "ipprotocol": rule.findtext("ipprotocol") or "inet",
            "protocol": rule.findtext("protocol") or "any",
            "source": source,
            "destination": destination,
        }
        if source_port:
            entry["source_port"] = source_port
        if destination_port:
            entry["destination_port"] = destination_port
        if rule.findtext("icmptype"):
            entry["icmptype"] = rule.findtext("icmptype")
        if (rule.findtext("statetype") or "keep state") != "keep state":
            entry["statetype"] = rule.findtext("statetype")
        for flag in ("disabled", "log", "quick", "floating"):
            if rule.find(flag) is not None:
                entry[flag] = True
        rules.append(entry)

    nat_port_forwards = []
    for nat in root.findall("./nat/rule"):
        source, source_port = _address(nat.find("source"))
        destination, destination_port = _address(nat.find("destination"))
        target = nat.findtext("target") or ""
        if nat.findtext("local-port"):
            target += ":" + nat.findtext("local-port")
        entry = {
            "descr": nat.findtext("descr"),
            "interface": nat.findtext("interface"),
            "ipprotocol": nat.findtext("ipprotocol") or "inet",
            "protocol": nat.findtext("protocol") or "tcp",
            "source": source + (":" + source_port if source_port else ""),
            "destination": destination + (":" + destination_port if destination_port else ""),
            "target": target,
            # The filter rule follows the port forward (created, updated,
            # deleted with it): that is why it is not in "rules".
            "associated_rule": "associated" if nat.findtext("associated-rule-id") else "none",
        }
        if nat.findtext("natreflection"):
            entry["natreflection"] = nat.findtext("natreflection")
        for flag in ("disabled", "nordr"):
            if nat.find(flag) is not None:
                entry[flag] = True
        nat_port_forwards.append(entry)

    gateways = []
    for gw in root.findall("./gateways/gateway_item"):
        entry = {
            "name": gw.findtext("name"),
            "interface": gw.findtext("interface"),
            "ipprotocol": gw.findtext("ipprotocol") or "inet",
            "gateway": gw.findtext("gateway"),
            "descr": gw.findtext("descr") or "",
            "weight": int(gw.findtext("weight") or 1),
        }
        if gw.findtext("monitor"):
            entry["monitor"] = gw.findtext("monitor")
        for xml_flag, option in (("disabled", "disabled"), ("monitor_disable", "monitor_disable"),
                                 ("action_disable", "action_disable"), ("force_down", "force_down"),
                                 ("nonlocalgateway", "nonlocalgateway")):
            if gw.find(xml_flag) is not None:
                entry[option] = True
        gateways.append(entry)

    routes = []
    for route in root.findall("./staticroutes/route"):
        entry = {
            "descr": route.findtext("descr") or "",
            "network": route.findtext("network"),
            "gateway": route.findtext("gateway"),
        }
        if route.find("disabled") is not None:
            entry["disabled"] = True
        routes.append(entry)

    system = root.find("system")
    setup = {
        "hostname": system.findtext("hostname"),
        "domain": system.findtext("domain"),
        "timezone": system.findtext("timezone"),
        "timeservers": system.findtext("timeservers") or "",
        "language": system.findtext("language") or "en_US",
        "dns_addresses": " ".join(x.text for x in system.findall("dnsserver") if x.text),
        "dnsallowoverride": system.find("dnsallowoverride") is not None,
    }
    # dns<N>host / dns<N>gw follow the order of the DNS servers.
    count = len(system.findall("dnsserver"))
    setup["dns_hostnames"] = " ".join(system.findtext(f"dns{i}host") or "" for i in range(1, count + 1))
    setup["dns_gateways"] = " ".join(system.findtext(f"dns{i}gw") or "none" for i in range(1, count + 1))

    unbound = root.find("unbound")
    dns_resolver = {
        "state": "present" if unbound.find("enable") is not None else "absent",
        "dnssec": unbound.find("dnssec") is not None,
        "active_interface": [x for x in (unbound.findtext("active_interface") or "").split(",") if x],
        "hideidentity": unbound.find("hideidentity") is not None,
        "hideversion": unbound.find("hideversion") is not None,
        "dnssecstripped": unbound.find("dnssecstripped") is not None,
        "hosts": [
            {key: host.findtext(key) or "" for key in ("host", "domain", "ip", "descr")}
            for host in unbound.findall("hosts")
        ],
        "domainoverrides": [
            {key: override.findtext(key) or "" for key in ("domain", "ip", "descr")}
            for override in unbound.findall("domainoverrides")
        ],
    }

    # Only enabled DHCP servers: a disabled one with a leftover range (lan)
    # carries no configuration worth keeping.
    dhcp_servers = []
    for iface in root.find("dhcpd") if root.find("dhcpd") is not None else []:
        if iface.find("enable") is None:
            continue
        dhcp_servers.append({
            "interface": iface.tag,
            "enable": True,
            "range_from": iface.findtext("range/from"),
            "range_to": iface.findtext("range/to"),
        })

    return {
        "setup": setup,
        "dns_resolver": dns_resolver,
        "dhcp_servers": dhcp_servers,
        "aliases": aliases,
        "rules": rules,
        "nat_port_forwards": nat_port_forwards,
        "gateways": gateways,
        "default_gateway": root.findtext("./gateways/defaultgw4") or "",
        "routes": routes,
    }


class FilterModule:
    def filters(self):
        return {"pfsense_resources_from_config": pfsense_resources_from_config}
