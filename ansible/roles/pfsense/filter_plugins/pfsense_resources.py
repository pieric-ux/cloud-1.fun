# Turns a pfSense config.xml into the host_vars/<firewall>/pfsense_resources.yml
# format (pfsensible.core pfsense_aggregate), so the conversion is versioned
# and reproducible.

import base64
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


def _secret(secrets, key, value):
    """Keep the value aside and return a reference to the vault variable."""
    if secrets is None:
        return value
    secrets[key] = value
    return "{{ vault_pfsense_secrets['%s'] }}" % key


def _flag(element, tag):
    """pfSense booleans: tag present (or "enabled") is true, "disabled" false."""
    node = element.find(tag)
    return node is not None and (node.text or "").strip() != "disabled"


def pfsense_resources_from_config(config_xml, secrets=None):
    """config.xml -> pfsense_resources. With a dict as secrets, keys,
    certificates, password hashes and TLS keys are moved into it and replaced
    by references to vault_pfsense_secrets."""
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

    interfaces = []
    for iface in root.find("interfaces"):
        entry = {
            "descr": iface.findtext("descr") or iface.tag.upper(),
            "interface": iface.findtext("if"),
            "enable": iface.find("enable") is not None,
            # Only static IPv4 here; no IPv6 address is configured (the LAN
            # track6 keys are leftovers without address).
            "ipv4_type": "static" if iface.findtext("ipaddr") else "none",
            "ipv6_type": "none",
            "blockpriv": iface.find("blockpriv") is not None,
            "blockbogons": iface.find("blockbogons") is not None,
        }
        if iface.findtext("ipaddr"):
            entry["ipv4_address"] = iface.findtext("ipaddr")
            entry["ipv4_prefixlen"] = int(iface.findtext("subnet"))
        if iface.findtext("gateway"):
            entry["ipv4_gateway"] = iface.findtext("gateway")
        if iface.findtext("mtu"):
            entry["mtu"] = int(iface.findtext("mtu"))
        interfaces.append(entry)

    refs = {ca.findtext("refid"): ca.findtext("descr") for ca in root.findall("./ca")}
    refs.update({cert.findtext("refid"): cert.findtext("descr") for cert in root.findall("./cert")})

    cas = []
    for ca in root.findall("./ca"):
        name = ca.findtext("descr")
        cas.append({
            "name": name,
            "trust": _flag(ca, "trust"),
            "randomserial": _flag(ca, "randomserial"),
            "certificate": _secret(secrets, "ca/%s/crt" % name, ca.findtext("crt")),
            "key": _secret(secrets, "ca/%s/key" % name, ca.findtext("prv")),
        })

    certs = []
    for cert in root.findall("./cert"):
        # Self-signed certificates (the web UI one, generated and renewed by
        # pfSense itself on install) have no CA and cannot be managed by
        # pfsense_cert: left to pfSense.
        if not cert.findtext("caref"):
            continue
        name = cert.findtext("descr")
        entry = {
            "name": name,
            "certtype": cert.findtext("type") or "user",
            "certificate": _secret(secrets, "cert/%s/crt" % name, cert.findtext("crt")),
            "key": _secret(secrets, "cert/%s/key" % name, cert.findtext("prv")),
        }
        if cert.findtext("caref"):
            entry["ca"] = refs[cert.findtext("caref")]
        certs.append(entry)

    users = []
    for user in root.findall("./system/user"):
        name = user.findtext("name")
        groups = [g.findtext("name") for g in root.findall("./system/group")
                  if user.findtext("uid") in [m.text for m in g.findall("member")]]
        entry = {
            "name": name,
            "descr": user.findtext("descr") or "",
            "scope": user.findtext("scope") or "user",
            "uid": user.findtext("uid"),
            "groups": groups,
            "priv": [p.text for p in user.findall("priv")],
            "password": _secret(secrets, "user/%s/password" % name, user.findtext("bcrypt-hash")),
        }
        keys = base64.b64decode(user.findtext("authorizedkeys") or "").decode()
        if keys:
            entry["authorizedkeys"] = keys
        if user.find("disabled") is not None:
            entry["disabled"] = True
        users.append(entry)

    openvpn_servers = []
    for server in root.findall("./openvpn/openvpn-server"):
        name = server.findtext("description")
        text = lambda tag: server.findtext(tag) or ""  # noqa: E731
        entry = {
            "name": name,
            "mode": text("mode"),
            "protocol": text("protocol"),
            "dev_mode": text("dev_mode"),
            "interface": text("interface"),
            "local_port": int(text("local_port")),
            "ca": refs.get(text("caref"), ""),
            "cert": refs.get(text("certref"), ""),
            "cert_depth": int(text("cert_depth") or 1),
            "remote_cert_tls": _flag(server, "remote_cert_tls") and bool(text("remote_cert_tls")),
            "dh_length": int(text("dh_length")),
            "ecdh_curve": text("ecdh_curve"),
            "digest": text("digest"),
            "data_ciphers": [c for c in text("data_ciphers").split(",") if c],
            "data_ciphers_fallback": text("data_ciphers_fallback"),
            "tunnel_network": text("tunnel_network"),
            "local_network": text("local_network"),
            "topology": text("topology"),
            "maxclients": int(text("maxclients") or 0),
            "allow_compression": text("allow_compression"),
            "dns_domain": text("dns_domain"),
            "dns_server1": text("dns_server1"),
            "username_as_common_name": text("username_as_common_name") == "enabled",
            "exit_notify": text("exit_notify"),
            "create_gw": text("create_gw"),
            "verbosity_level": int(text("verbosity_level") or 1),
            "keepalive_interval": int(text("keepalive_interval") or 10),
            "keepalive_timeout": int(text("keepalive_timeout") or 60),
            "inactive_seconds": int(text("inactive_seconds") or 0),
            "custom_options": text("custom_options"),
        }
        if "tls" in entry["mode"] and text("tls"):
            # Stored with CRLF line endings when pasted from a browser:
            # pfsensible only recognises the key with LF endings.
            tls_key = base64.b64decode(text("tls")).decode().replace("\r\n", "\n")
            tls_key = base64.b64encode(tls_key.encode()).decode()
            entry["tls"] = _secret(secrets, "openvpn/%s/tls" % name, tls_key)
            entry["tls_type"] = text("tls_type")
        openvpn_servers.append(entry)

    return {
        "setup": setup,
        "cas": cas,
        "certs": certs,
        "users": users,
        "openvpn_servers": openvpn_servers,
        "interfaces": interfaces,
        "dns_resolver": dns_resolver,
        "dhcp_servers": dhcp_servers,
        "aliases": aliases,
        "rules": rules,
        "nat_port_forwards": nat_port_forwards,
        "gateways": gateways,
        "default_gateway": root.findtext("./gateways/defaultgw4") or "",
        "routes": routes,
    }


def pfsense_resources_with_refs(config_xml):
    """pfsense_resources with every secret replaced by a vault reference."""
    return pfsense_resources_from_config(config_xml, secrets={})


def pfsense_secrets_from_config(config_xml):
    """The secrets matching pfsense_resources_with_refs (for vault.yml)."""
    secrets = {}
    pfsense_resources_from_config(config_xml, secrets=secrets)
    return secrets


class FilterModule:
    def filters(self):
        return {
            "pfsense_resources_from_config": pfsense_resources_from_config,
            "pfsense_secrets_from_config": pfsense_secrets_from_config,
            "pfsense_resources_with_refs": pfsense_resources_with_refs,
        }
