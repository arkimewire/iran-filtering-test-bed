#!/usr/bin/env python3
"""
NFQUEUE Packet Inspection Daemon

Replaces iptables -m string matching for kernel 6.17+ compatibility.
Receives packets via nftables queue verdicts, inspects payloads for
configured patterns (HTTP Host, SNI, hex signatures), and issues
ACCEPT/DROP verdicts.

Queue assignments:
  1 - HTTP Host filtering (2.1)
  2 - SNI filtering (4.1)
  3 - TLS fingerprinting (4.2)
  4 - TCP RST injection via SNI (4.3)
  5 - Encapsulated protocol detection (5.1)
  6 - DoH/DoT DPI: ALPN + SNI (1.2)
"""

import os
import sys
import struct
import signal
import threading
from netfilterqueue import NetfilterQueue

BLOCKLIST_DIR = "/etc/nfqueue"
PRIV_MARK = 0x10


def load_lines(path):
    try:
        with open(path) as f:
            return [
                l.strip()
                for l in f
                if l.strip() and not l.strip().startswith("#")
            ]
    except FileNotFoundError:
        return []


def load_hex_signatures(path):
    sigs = []
    for line in load_lines(path):
        if ":" in line:
            raw = line.split(":", 1)[1]
        else:
            raw = line
        raw = raw.strip().strip("|").replace(" ", "")
        try:
            sigs.append(bytes.fromhex(raw))
        except ValueError:
            pass
    return sigs


def parse_sni(data):
    if len(data) < 5 or data[0] != 0x16:
        return None
    record_len = struct.unpack("!H", data[3:5])[0]
    full_record = data[5 : 5 + record_len]
    if len(full_record) < record_len or len(full_record) < 4:
        return None
    if full_record[0] != 0x01:
        return None
    hs_len = struct.unpack("!I", b"\x00" + full_record[1:4])[0]
    hs_data = full_record[4 : 4 + hs_len]
    if len(hs_data) < 38:
        return None
    offset = 34
    if offset >= len(hs_data):
        return None
    session_id_len = hs_data[offset]
    offset += 1 + session_id_len
    if offset + 2 > len(hs_data):
        return None
    cipher_suites_len = struct.unpack("!H", hs_data[offset : offset + 2])[0]
    offset += 2 + cipher_suites_len
    if offset >= len(hs_data):
        return None
    comp_methods_len = hs_data[offset]
    offset += 1 + comp_methods_len
    if offset + 2 > len(hs_data):
        return None
    extensions_len = struct.unpack("!H", hs_data[offset : offset + 2])[0]
    offset += 2
    extensions_end = offset + extensions_len
    while offset + 4 <= extensions_end:
        ext_type = struct.unpack("!H", hs_data[offset : offset + 2])[0]
        ext_len = struct.unpack("!H", hs_data[offset + 2 : offset + 4])[0]
        offset += 4
        if ext_type == 0x0000:
            if offset + 2 > extensions_end:
                break
            sni_offset = offset + 2
            sni_list_len = struct.unpack("!H", hs_data[offset : offset + 2])[0]
            sni_end = sni_offset + sni_list_len
            while sni_offset + 3 <= sni_end:
                name_type = hs_data[sni_offset]
                name_len = struct.unpack(
                    "!H", hs_data[sni_offset + 1 : sni_offset + 3]
                )[0]
                sni_offset += 3
                if name_type == 0 and sni_offset + name_len <= len(hs_data):
                    return hs_data[sni_offset : sni_offset + name_len].decode(
                        "ascii", errors="ignore"
                    )
                sni_offset += name_len
        offset += ext_len
    return None


def domain_matches(sni, domains):
    if not sni:
        return False
    sni = sni.lower()
    for d in domains:
        if sni == d or sni.endswith("." + d):
            return True
    return False


def get_tcp_payload(raw):
    if len(raw) < 20:
        return b""
    ihl = (raw[0] & 0x0F) * 4
    if len(raw) < ihl + 20:
        return b""
    tcp_offset = ihl
    tcp_data_offset = (raw[tcp_offset + 12] >> 4) * 4
    payload_start = tcp_offset + tcp_data_offset
    return raw[payload_start:]


def get_full_payload(raw):
    if len(raw) < 20:
        return b""
    ihl = (raw[0] & 0x0F) * 4
    proto = raw[9]
    if proto == 6:  # TCP
        if len(raw) < ihl + 20:
            return b""
        tcp_offset = ihl
        tcp_data_offset = (raw[tcp_offset + 12] >> 4) * 4
        return raw[tcp_offset + tcp_data_offset :]
    elif proto == 17:  # UDP
        if len(raw) < ihl + 8:
            return b""
        return raw[ihl + 8 :]
    return raw[ihl:]


def is_privileged(raw):
    if len(raw) < 20:
        return False
    # nftables marks packets before they reach the queue, but for safety
    # we don't check the mark here -- the nft rules already skip privileged
    # traffic via "meta mark $PRIV_MARK accept" before the queue rule.
    return False


# --- Queue handlers ---

class HTTPHostFilter:
    def __init__(self):
        self.domains = set()

    def load(self):
        self.domains = set(
            d.lower() for d in load_lines(BLOCKLIST_DIR + "/http_blocklist.conf")
        )

    def handle(self, pkt):
        payload = get_tcp_payload(pkt.get_payload())
        if not payload:
            pkt.accept()
            return
        try:
            text = payload.decode("ascii", errors="ignore")
        except Exception:
            pkt.accept()
            return
        for line in text.split("\r\n"):
            if line.lower().startswith("host:"):
                host = line.split(":", 1)[1].strip().lower()
                host = host.split(":")[0]  # strip port
                if host in self.domains:
                    pkt.drop()
                    return
                for d in self.domains:
                    if host.endswith("." + d):
                        pkt.drop()
                        return
        pkt.accept()


class SNIFilter:
    def __init__(self):
        self.domains = set()

    def load(self):
        self.domains = set(
            d.lower() for d in load_lines(BLOCKLIST_DIR + "/sni_blocklist.conf")
        )

    def handle(self, pkt):
        payload = get_tcp_payload(pkt.get_payload())
        sni = parse_sni(payload)
        if domain_matches(sni, self.domains):
            pkt.drop()
        else:
            pkt.accept()


class TLSFingerprintFilter:
    def __init__(self):
        self.signatures = []

    def load(self):
        self.signatures = load_hex_signatures(
            BLOCKLIST_DIR + "/tls_signatures.conf"
        )

    def handle(self, pkt):
        payload = get_tcp_payload(pkt.get_payload())
        if payload:
            for sig in self.signatures:
                if sig in payload:
                    pkt.drop()
                    return
        pkt.accept()


class SNIRSTFilter:
    """Same as SNI filter but uses REJECT (drop simulates RST for nfqueue)."""

    def __init__(self):
        self.domains = set()

    def load(self):
        self.domains = set(
            d.lower() for d in load_lines(BLOCKLIST_DIR + "/sni_blocklist.conf")
        )

    def handle(self, pkt):
        payload = get_tcp_payload(pkt.get_payload())
        sni = parse_sni(payload)
        if domain_matches(sni, self.domains):
            pkt.drop()
        else:
            pkt.accept()


class EncapsulatedProtoFilter:
    def __init__(self):
        self.signatures = []

    def load(self):
        self.signatures = load_hex_signatures(
            BLOCKLIST_DIR + "/encapsulated_signatures.conf"
        )

    def handle(self, pkt):
        payload = get_full_payload(pkt.get_payload())
        if payload:
            for sig in self.signatures:
                if sig in payload:
                    pkt.drop()
                    return
        pkt.accept()


class DoHDoTDPIFilter:
    """Inspects for ALPN 'dot' pattern and DNS provider SNI hostnames."""

    def __init__(self):
        self.alpn_pattern = b"\x03dot"
        self.hostnames = set()

    def load(self):
        lines = load_lines(BLOCKLIST_DIR + "/doh_dot_providers.conf")
        self.hostnames = set()
        for line in lines:
            if line.startswith("hostname:"):
                self.hostnames.add(line.split(":", 1)[1].strip().lower())

    def handle(self, pkt):
        payload = get_tcp_payload(pkt.get_payload())
        if not payload:
            pkt.accept()
            return
        if self.alpn_pattern in payload:
            pkt.drop()
            return
        sni = parse_sni(payload)
        if sni and sni.lower() in self.hostnames:
            pkt.drop()
            return
        pkt.accept()


QUEUES = {
    1: ("http_host", HTTPHostFilter),
    2: ("sni_filter", SNIFilter),
    3: ("tls_fingerprint", TLSFingerprintFilter),
    4: ("sni_rst", SNIRSTFilter),
    5: ("encapsulated_proto", EncapsulatedProtoFilter),
    6: ("doh_dot_dpi", DoHDoTDPIFilter),
}


def run_queue(queue_num, handler):
    nfq = NetfilterQueue()
    nfq.bind(queue_num, handler)
    try:
        nfq.run()
    except Exception:
        pass
    finally:
        nfq.unbind()


def main():
    queues_to_run = []
    if len(sys.argv) > 1:
        for arg in sys.argv[1:]:
            try:
                q = int(arg)
                if q in QUEUES:
                    queues_to_run.append(q)
            except ValueError:
                pass

    if not queues_to_run:
        print(f"Usage: {sys.argv[0]} <queue_num> [queue_num ...]")
        print(f"Available queues: {list(QUEUES.keys())}")
        sys.exit(1)

    threads = []
    for q in queues_to_run:
        name, cls = QUEUES[q]
        handler = cls()
        handler.load()
        print(f"Starting queue {q} ({name})")
        t = threading.Thread(target=run_queue, args=(q, handler.handle), daemon=True)
        t.start()
        threads.append(t)

    def shutdown(signum, frame):
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
