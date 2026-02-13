#!/usr/bin/env python3
"""
TCP Stream Reassembly Proxy for SNI Inspection (5.2)

Simulates the GFW's primary countermeasure against TCP segmentation / TLS
record fragmentation bypass techniques.  Anti-filtering tools (GoodbyeDPI,
zapret, MahsaNG) split the TLS ClientHello across multiple TCP segments so
no single packet contains the full SNI.  This proxy defeats that by
reassembling the TCP stream (as a real DPI box would) and extracting the
SNI from the reconstructed ClientHello.

Architecture:
  iptables REDIRECT sends port-443 traffic to this proxy on port 8443.
  The proxy accepts the connection, reads enough data to reconstruct the
  full ClientHello, parses the SNI, and either:
    - resets the connection if the SNI is on the blocklist, or
    - forwards the traffic transparently to the original destination.

This uses only Python3 standard library (socket, struct, select, threading).
"""

import os
import sys
import socket
import struct
import select
import threading
import signal

SO_ORIGINAL_DST = 80
LISTEN_PORT = 8443
BLOCKLIST_PATH = "/etc/sni_blocklist.conf"
BUFFER_SIZE = 8192
CLIENTHELLO_TIMEOUT = 5  # seconds to wait for full ClientHello

blocked_domains = set()


def load_blocklist():
    global blocked_domains
    try:
        with open(BLOCKLIST_PATH, "r") as f:
            domains = set()
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    domains.add(line.lower())
            blocked_domains = domains
    except FileNotFoundError:
        blocked_domains = set()


def get_original_dst(sock):
    """Get the original destination address before REDIRECT."""
    dst = sock.getsockopt(socket.SOL_IP, SO_ORIGINAL_DST, 16)
    port = struct.unpack("!H", dst[2:4])[0]
    ip = socket.inet_ntoa(dst[4:8])
    return ip, port


def parse_sni(data):
    """Extract SNI from a TLS ClientHello (possibly reassembled from fragments).

    Returns the SNI hostname string, or None if not found / not a ClientHello.
    """
    if len(data) < 5:
        return None

    # TLS record header: ContentType(1) + Version(2) + Length(2)
    content_type = data[0]
    if content_type != 0x16:  # Handshake
        return None

    # We may have received multiple TLS records or a partial one.
    # Try to get the full record.
    record_len = struct.unpack("!H", data[3:5])[0]
    full_record = data[5 : 5 + record_len]

    if len(full_record) < record_len:
        return None  # incomplete record

    # Handshake header: Type(1) + Length(3)
    if len(full_record) < 4:
        return None
    handshake_type = full_record[0]
    if handshake_type != 0x01:  # ClientHello
        return None

    hs_len = struct.unpack("!I", b"\x00" + full_record[1:4])[0]
    hs_data = full_record[4 : 4 + hs_len]

    if len(hs_data) < 38:
        return None

    # Skip: Version(2) + Random(32) = 34 bytes
    offset = 34

    # Session ID
    if offset >= len(hs_data):
        return None
    session_id_len = hs_data[offset]
    offset += 1 + session_id_len

    # Cipher Suites
    if offset + 2 > len(hs_data):
        return None
    cipher_suites_len = struct.unpack("!H", hs_data[offset : offset + 2])[0]
    offset += 2 + cipher_suites_len

    # Compression Methods
    if offset >= len(hs_data):
        return None
    comp_methods_len = hs_data[offset]
    offset += 1 + comp_methods_len

    # Extensions
    if offset + 2 > len(hs_data):
        return None
    extensions_len = struct.unpack("!H", hs_data[offset : offset + 2])[0]
    offset += 2
    extensions_end = offset + extensions_len

    while offset + 4 <= extensions_end:
        ext_type = struct.unpack("!H", hs_data[offset : offset + 2])[0]
        ext_len = struct.unpack("!H", hs_data[offset + 2 : offset + 4])[0]
        offset += 4

        if ext_type == 0x0000:  # SNI extension
            if offset + 2 > extensions_end:
                break
            sni_list_len = struct.unpack("!H", hs_data[offset : offset + 2])[0]
            sni_offset = offset + 2
            sni_end = sni_offset + sni_list_len

            while sni_offset + 3 <= sni_end:
                name_type = hs_data[sni_offset]
                name_len = struct.unpack(
                    "!H", hs_data[sni_offset + 1 : sni_offset + 3]
                )[0]
                sni_offset += 3

                if name_type == 0:  # host_name
                    if sni_offset + name_len <= len(hs_data):
                        return hs_data[sni_offset : sni_offset + name_len].decode(
                            "ascii", errors="ignore"
                        )
                sni_offset += name_len

        offset += ext_len

    return None


def is_blocked(sni):
    """Check if an SNI matches the blocklist (exact or subdomain)."""
    if not sni:
        return False
    sni = sni.lower()
    if sni in blocked_domains:
        return True
    for domain in blocked_domains:
        if sni.endswith("." + domain):
            return True
    return False


def relay(src, dst):
    """Relay data between two sockets until one closes."""
    try:
        while True:
            readable, _, _ = select.select([src, dst], [], [], 30)
            if not readable:
                break
            for s in readable:
                data = s.recv(BUFFER_SIZE)
                if not data:
                    return
                target = dst if s is src else src
                target.sendall(data)
    except (OSError, BrokenPipeError):
        pass


def handle_client(client_sock, client_addr):
    """Handle one redirected connection."""
    upstream_sock = None
    try:
        orig_ip, orig_port = get_original_dst(client_sock)

        # Read the ClientHello (may arrive in multiple TCP segments)
        client_sock.settimeout(CLIENTHELLO_TIMEOUT)
        data = b""
        while len(data) < BUFFER_SIZE:
            try:
                chunk = client_sock.recv(BUFFER_SIZE - len(data))
            except socket.timeout:
                break
            if not chunk:
                return
            data += chunk

            # Check if we have a complete TLS record
            if len(data) >= 5:
                record_len = struct.unpack("!H", data[3:5])[0]
                if len(data) >= 5 + record_len:
                    break  # got the full record

        client_sock.settimeout(None)

        sni = parse_sni(data)

        if is_blocked(sni):
            # RST the connection -- simulates GFW dropping after reassembly
            client_sock.setsockopt(
                socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0)
            )
            client_sock.close()
            return

        # SNI is allowed (or not detected) -- forward transparently
        upstream_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        upstream_sock.settimeout(5)
        upstream_sock.connect((orig_ip, orig_port))
        upstream_sock.settimeout(None)

        # Send the buffered ClientHello to the upstream
        upstream_sock.sendall(data)

        # Relay bidirectionally
        relay(client_sock, upstream_sock)

    except Exception:
        pass
    finally:
        try:
            client_sock.close()
        except OSError:
            pass
        if upstream_sock:
            try:
                upstream_sock.close()
            except OSError:
                pass


def main():
    load_blocklist()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", LISTEN_PORT))
    server.listen(128)

    def shutdown(signum, frame):
        server.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    while True:
        try:
            client_sock, client_addr = server.accept()
            t = threading.Thread(
                target=handle_client, args=(client_sock, client_addr), daemon=True
            )
            t.start()
        except OSError:
            break


if __name__ == "__main__":
    main()
