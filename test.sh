#!/bin/bash
#
# Test script for the Iran filtering simulation.
# Run after: clab destroy && ./build.sh && clab deploy
#
# Verifies connectivity, all filtering mechanisms, and their on/off behavior.

set -uo pipefail

source scripts/common.sh 2>/dev/null || source "$(dirname "$0")/scripts/common.sh"
echo "Detected topology: $TOPOLOGY"

PASS=0
FAIL=0

C="$CLAB_PREFIX"

BB=$(resolve_container BACKBONE)
ISP_C=$(resolve_container ISP)
CLIENT=$(resolve_container CLIENT)
INTRANET=$(resolve_container INTRANET)
INTERNET=$(resolve_container INTERNET_SRV)
BB_INT_IF=$(resolve_interface BACKBONE internal)

run() {
    docker exec "$C-$1" bash -c "$2"
}

run_c() {
    docker exec "$1" bash -c "$2"
}

assert_pass() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $name"
        ((PASS++))
    else
        echo "  FAIL: $name"
        ((FAIL++))
    fi
}

assert_fail() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $name (expected failure but succeeded)"
        ((FAIL++))
    else
        echo "  PASS: $name"
        ((PASS++))
    fi
}

assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $name"
        ((PASS++))
    else
        echo "  FAIL: $name (expected '$expected', got '$actual')"
        ((FAIL++))
    fi
}

assert_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $name"
        ((PASS++))
    else
        echo "  FAIL: $name (expected to contain '$needle')"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  FAIL: $name (should NOT contain '$needle')"
        ((FAIL++))
    else
        echo "  PASS: $name"
        ((PASS++))
    fi
}

restart_tls_server() {
    # Kill old server safely by process name
    docker exec "$INTERNET" killall -9 openssl 2>/dev/null || true
    sleep 1
    # Start new server
    run_c "$INTERNET" "nohup openssl s_server -key /tmp/key.pem -cert /tmp/cert.pem -accept 443 -www >/dev/null 2>&1 &"
    for i in 1 2 3 4 5; do
        docker exec "$INTERNET" ss -tln | grep -q :443 && return
        sleep 1
    done
}

# ---------------------------------------------------------------------------
echo "=== 1. Container health ==="
# ---------------------------------------------------------------------------

for node in $(topology_nodes); do
    assert_pass "$node is running" \
        docker exec "$C-$node" true
done

# ---------------------------------------------------------------------------
echo ""
echo "=== 2. Network connectivity (layer 3) ==="
# ---------------------------------------------------------------------------

ISP_IP=$(resolve_ip ISP self)
INTERNET_IP=$(resolve_ip INTERNET_SRV self)
INTRANET_IP=$(resolve_ip INTRANET self)

assert_pass "client -> ISP ($ISP_IP)" \
    run_c "$CLIENT" "ping -c1 -W3 $ISP_IP"

assert_pass "backbone -> internet-srv ($INTERNET_IP)" \
    run_c "$BB" "ping -c1 -W3 $INTERNET_IP"

assert_pass "client -> internet-srv full chain ($INTERNET_IP)" \
    run_c "$CLIENT" "ping -c1 -W3 $INTERNET_IP"

assert_pass "client -> intranet ($INTRANET_IP)" \
    run_c "$CLIENT" "ping -c1 -W3 $INTRANET_IP"

assert_pass "backbone -> real internet (1.1.1.1)" \
    run_c "$BB" "ping -c1 -W3 1.1.1.1"

assert_pass "client -> real internet (1.1.1.1)" \
    run_c "$CLIENT" "ping -c1 -W3 1.1.1.1"

# ---------------------------------------------------------------------------
echo ""
echo "=== 3. DNS resolution (unblocked domains) ==="
# ---------------------------------------------------------------------------

GOOGLE_IP=$(run_c "$CLIENT" "dig @8.8.8.8 google.com A +tcp +short +timeout=5 2>/dev/null" | head -1)
assert_pass "client resolves google.com via DNS" \
    test -n "$GOOGLE_IP"

assert_pass "client can ping google.com" \
    run_c "$CLIENT" "ping -4 -c1 -W5 google.com"

assert_pass "client can curl google.com" \
    run_c "$CLIENT" "curl -sI --connect-timeout 5 -m 10 http://google.com"

# ---------------------------------------------------------------------------
echo ""
echo "=== 4. Service & system verification ==="
# ---------------------------------------------------------------------------

ISP_DNSMASQ=$(run_c "$ISP_C" "pgrep -x dnsmasq" 2>/dev/null || true)
assert_pass "dnsmasq running on ISP" \
    test -n "$ISP_DNSMASQ"

BB_DNSMASQ=$(run_c "$BB" "pgrep -x dnsmasq" 2>/dev/null || true)
assert_pass "dnsmasq running on backbone" \
    test -n "$BB_DNSMASQ"

fwd_bb=$(run_c "$BB" "cat /proc/sys/net/ipv4/ip_forward" 2>/dev/null)
assert_eq "backbone has ip_forward=1" "1" "$fwd_bb"

fwd_isp=$(run_c "$ISP_C" "cat /proc/sys/net/ipv4/ip_forward" 2>/dev/null)
assert_eq "ISP has ip_forward=1" "1" "$fwd_isp"

# ===========================================================================
# FILTERING MECHANISM TESTS
# Each section: verify initially OFF, enable, test, disable, verify restored.
# ===========================================================================

# --- Set up test servers on internet-srv (used by multiple test sections) ---
# HTTP servers on port 80 and 8080 (python3 http.server handles concurrent requests)
run_c "$INTERNET" "bash -c 'echo HTTP_OK > /tmp/index.html'"
run_c "$INTERNET" "bash -c 'cd /tmp && nohup python3 -m http.server 80 >/dev/null 2>&1 &'"
run_c "$INTERNET" "bash -c 'cd /tmp && nohup python3 -m http.server 8080 >/dev/null 2>&1 &'"
# TLS server on port 443
run_c "$INTERNET" "bash -c 'openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/cert.pem -days 1 -nodes -subj /CN=test 2>/dev/null'"
run_c "$INTERNET" "bash -c 'nohup openssl s_server -key /tmp/key.pem -cert /tmp/cert.pem -accept 443 -www >/dev/null 2>&1 &'"
sleep 2

# Verify test servers are running
assert_pass "test HTTP server on internet-srv:80 is ready" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 http://203.0.113.2/"
assert_pass "test TLS server on internet-srv:443 is ready" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 https://203.0.113.2/"

# ---------------------------------------------------------------------------
echo ""
echo "=== 5. DNS Hijacking (1.1) ==="
# ---------------------------------------------------------------------------

assert_contains "1.1 initially OFF" "OFF" "$(./scripts/1.1-dns-hijacking.sh status)"

./scripts/1.1-dns-hijacking.sh on > /dev/null

DNS_BLOCKED_DOMAINS=$(grep "^address=" config/isp/blocklist.conf | cut -d/ -f2)
for domain in $DNS_BLOCKED_DOMAINS; do
    resolved=$(run_c "$CLIENT" "dig @8.8.8.8 $domain A +tcp +short +timeout=5 2>/dev/null" | head -1)
    assert_eq "1.1 ON: $domain -> 10.10.34.34" "10.10.34.34" "$resolved"
done

# Non-blocked domain should still resolve normally during hijacking
UNBLOCKED_IP=$(run_c "$CLIENT" "dig @8.8.8.8 google.com A +tcp +short +timeout=5 2>/dev/null" | head -1)
assert_not_contains "1.1 ON: google.com NOT hijacked" "10.10.34.34" "$UNBLOCKED_IP"

./scripts/1.1-dns-hijacking.sh off > /dev/null
assert_contains "1.1 OFF after disable" "OFF" "$(./scripts/1.1-dns-hijacking.sh status)"

# Verify DNS works normally after disabling
RESTORED_IP=$(run_c "$CLIENT" "dig @8.8.8.8 x.com A +tcp +short +timeout=5 2>/dev/null" | head -1)
assert_not_contains "1.1 OFF: x.com no longer hijacked" "10.10.34.34" "$RESTORED_IP"

# ---------------------------------------------------------------------------
echo ""
echo "=== 6. DoH/DoT Blocking (1.2) ==="
# ---------------------------------------------------------------------------

assert_contains "1.2 nftables initially OFF" "OFF" "$(./scripts/1.2-doh-dot-blocking.sh status)"

# Client can reach 1.1.1.1 before blocking
assert_pass "1.2 OFF: client can reach 1.1.1.1" \
    run_c "$CLIENT" "ping -c1 -W3 1.1.1.1"

./scripts/1.2-doh-dot-blocking.sh on > /dev/null

# Client cannot reach known DoH/DoT providers
assert_fail "1.2 ON: client cannot reach 1.1.1.1 (Cloudflare DNS)" \
    run_c "$CLIENT" "ping -c1 -W3 1.1.1.1"

assert_fail "1.2 ON: client cannot reach 8.8.8.8 (Google DNS)" \
    run_c "$CLIENT" "ping -c1 -W3 8.8.8.8"

./scripts/1.2-doh-dot-blocking.sh off > /dev/null

assert_pass "1.2 OFF: client can reach 1.1.1.1 again" \
    run_c "$CLIENT" "ping -c1 -W3 1.1.1.1"

# ---------------------------------------------------------------------------
echo ""
echo "=== 7. HTTP Host Filtering (2.1) ==="
# ---------------------------------------------------------------------------

assert_contains "2.1 initially OFF" "OFF" "$(./scripts/2.1-http-host-filtering.sh status)"

# Client can reach HTTP before filtering
assert_pass "2.1 OFF: HTTP to internet-srv works" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 -H 'Host: example.com' http://203.0.113.2/"

./scripts/2.1-http-host-filtering.sh on > /dev/null

# Client cannot fetch blocked HTTP host (example.com is in http_blocklist.conf)
assert_fail "2.1 ON: HTTP Host example.com is blocked" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 -H 'Host: example.com' http://203.0.113.2/"

# Unblocked host should still work
assert_pass "2.1 ON: HTTP Host allowed.com still works" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 -H 'Host: allowed.com' http://203.0.113.2/"

./scripts/2.1-http-host-filtering.sh off > /dev/null
assert_contains "2.1 OFF after disable" "OFF" "$(./scripts/2.1-http-host-filtering.sh status)"

# Verify previously blocked host works again after disabling
assert_pass "2.1 OFF: HTTP Host example.com works again" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 -H 'Host: example.com' http://203.0.113.2/"

# ---------------------------------------------------------------------------
echo ""
echo "=== 8. IP-based blocking (3.1) ==="
# ---------------------------------------------------------------------------

assert_contains "3.1 initially OFF" "OFF" "$(./scripts/3.1-ip-blocking.sh status)"

blocked_ips=$(grep -v '^#' config/backbone/blocklist.conf | grep -v '^[[:space:]]*$' | xargs)

for entry in $blocked_ips; do
    if echo "$entry" | grep -q '/'; then
        test_ip=$(echo "$entry" | sed 's|/.*||' | awk -F. '{printf "%s.%s.%s.%s", $1, $2, $3, ($4 == 0 ? 1 : $4)}')
    else
        test_ip="$entry"
    fi
    assert_pass "3.1 OFF: client can reach $test_ip" \
        run_c "$CLIENT" "ping -c1 -W2 $test_ip"
done

./scripts/3.1-ip-blocking.sh on > /dev/null

for entry in $blocked_ips; do
    if echo "$entry" | grep -q '/'; then
        test_ip=$(echo "$entry" | sed 's|/.*||' | awk -F. '{printf "%s.%s.%s.%s", $1, $2, $3, ($4 == 0 ? 1 : $4)}')
    else
        test_ip="$entry"
    fi
    assert_fail "3.1 ON: client cannot reach $test_ip" \
        run_c "$CLIENT" "ping -c1 -W3 $test_ip"
done

./scripts/3.1-ip-blocking.sh off > /dev/null
assert_contains "3.1 OFF after disable" "OFF" "$(./scripts/3.1-ip-blocking.sh status)"

# Verify previously blocked IP is reachable again
assert_pass "3.1 OFF: 172.66.0.227 reachable again" \
    run_c "$CLIENT" "ping -c1 -W3 172.66.0.227"

# ---------------------------------------------------------------------------
echo ""
echo "=== 9. BGP Hijacking (3.2) ==="
# ---------------------------------------------------------------------------

assert_contains "3.2 initially OFF" "OFF" "$(./scripts/3.2-bgp-hijacking.sh status)"

./scripts/3.2-bgp-hijacking.sh on > /dev/null
assert_contains "3.2 ON" "ACTIVE" "$(./scripts/3.2-bgp-hijacking.sh status)"

# Verify blackhole routes exist on backbone
bgp_prefixes=$(grep -v '^#' config/backbone/bgp_hijack.conf | grep -v '^[[:space:]]*$')
for prefix in $bgp_prefixes; do
    BLACKHOLE=$(docker exec "$BB" ip route show "$prefix" 2>/dev/null || true)
    assert_contains "3.2 ON: blackhole route for $prefix exists" "blackhole" "$BLACKHOLE"
done

# Traffic to blackholed prefix should fail from the client
assert_fail "3.2 ON: client cannot reach blackholed IP 93.184.216.34" \
    run_c "$CLIENT" "ping -c1 -W3 93.184.216.34"

./scripts/3.2-bgp-hijacking.sh off > /dev/null
assert_contains "3.2 OFF after disable" "OFF" "$(./scripts/3.2-bgp-hijacking.sh status)"

# Verify blackhole is gone -- route should no longer contain "blackhole"
ROUTE_AFTER=$(docker exec "$BB" ip route show 93.184.216.34/32 2>/dev/null || true)
assert_not_contains "3.2 OFF: blackhole route removed" "blackhole" "$ROUTE_AFTER"

# ---------------------------------------------------------------------------
echo ""
echo "=== 10. IPv6 Filtering (3.3) ==="
# ---------------------------------------------------------------------------

assert_contains "3.3 initially OFF" "OFF" "$(./scripts/3.3-ipv6-filtering.sh status)"

./scripts/3.3-ipv6-filtering.sh on > /dev/null
assert_contains "3.3 ON" "ON" "$(./scripts/3.3-ipv6-filtering.sh status)"

# Verify the nftables rule exists
IPV6_RULES=$(docker exec "$BB" nft list table ip6 ipv6_filter 2>/dev/null || true)
assert_contains "3.3 ON: ip6 forward drop rule exists" "drop" "$IPV6_RULES"

./scripts/3.3-ipv6-filtering.sh off > /dev/null
assert_contains "3.3 OFF after disable" "OFF" "$(./scripts/3.3-ipv6-filtering.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 11. SNI Filtering (4.1) ==="
# ---------------------------------------------------------------------------

assert_contains "4.1 initially OFF" "OFF" "$(./scripts/4.1-sni-filtering.sh status)"

# Client can connect to TLS before filtering
assert_pass "4.1 OFF: client can TLS connect to internet-srv:443" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 https://203.0.113.2/"

./scripts/4.1-sni-filtering.sh on > /dev/null

# Verify nftables queue rules are present
SNI_RULES=$(docker exec "$BB" nft list table ip sni_filter 2>/dev/null || true)
assert_contains "4.1 ON: SNI queue rules exist for port 443" "queue" "$SNI_RULES"

# Allowed SNI (not in blocklist) should still work
assert_pass "4.1 ON: TLS to allowed SNI works" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 --resolve allowed.example.com:443:203.0.113.2 https://allowed.example.com/"

# Client cannot connect with a blocked SNI (x.com is in sni_blocklist.conf)
# Note: this test is last because the blocked TLS handshake (TCP completes but
# ClientHello is dropped) can leave openssl s_server stuck on a half-open conn.
assert_fail "4.1 ON: TLS to x.com SNI is blocked" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 --resolve x.com:443:203.0.113.2 https://x.com/"

./scripts/4.1-sni-filtering.sh off > /dev/null
assert_contains "4.1 OFF after disable" "OFF" "$(./scripts/4.1-sni-filtering.sh status)"

# Restart the TLS server (previous blocked test may have left it stuck)
restart_tls_server

# Verify TLS works again after disabling
assert_pass "4.1 OFF: TLS to internet-srv restored" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 https://203.0.113.2/"

# ---------------------------------------------------------------------------
echo ""
echo "=== 12. TLS Fingerprinting (4.2) ==="
# ---------------------------------------------------------------------------

# TLS fingerprinting uses hex-pattern matching. We can't easily generate traffic
# matching mock patterns, so we verify the rules are created correctly.

assert_contains "4.2 initially OFF" "OFF" "$(./scripts/4.2-tls-fingerprinting.sh status)"

./scripts/4.2-tls-fingerprinting.sh on > /dev/null
assert_contains "4.2 ON" "ON" "$(./scripts/4.2-tls-fingerprinting.sh status)"

# Verify nftables queue rules exist
TLS_FP_RULES=$(docker exec "$BB" nft list table ip tls_fingerprint 2>/dev/null || true)
assert_contains "4.2 ON: tls_fingerprint table has queue rules" "queue" "$TLS_FP_RULES"

./scripts/4.2-tls-fingerprinting.sh off > /dev/null
assert_contains "4.2 OFF after disable" "OFF" "$(./scripts/4.2-tls-fingerprinting.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 13. TCP RST Injection (4.3) ==="
# ---------------------------------------------------------------------------

assert_contains "4.3 initially OFF" "OFF" "$(./scripts/4.3-tcp-rst-injection.sh status)"

./scripts/4.3-tcp-rst-injection.sh on > /dev/null
assert_contains "4.3 ON" "ON" "$(./scripts/4.3-tcp-rst-injection.sh status)"

# Verify nftables queue rules exist
RST_RULES=$(docker exec "$BB" nft list table ip sni_rst_filter 2>/dev/null || true)
assert_contains "4.3 ON: sni_rst_filter table has queue rules" "queue" "$RST_RULES"

# Client should fail to connect with blocked SNI (RST or timeout)
assert_fail "4.3 ON: TLS to x.com fails (RST injected)" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 --resolve x.com:443:203.0.113.2 https://x.com/"

./scripts/4.3-tcp-rst-injection.sh off > /dev/null
assert_contains "4.3 OFF after disable" "OFF" "$(./scripts/4.3-tcp-rst-injection.sh status)"

# Restart TLS server and verify TLS works again
restart_tls_server
assert_pass "4.3 OFF: TLS to internet-srv restored" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 https://203.0.113.2/"

# ---------------------------------------------------------------------------
echo ""
echo "=== 14. Encapsulated Protocol Detection (5.1) ==="
# ---------------------------------------------------------------------------

# Uses hex-pattern matching. Verify rules are created correctly.

assert_contains "5.1 initially OFF" "OFF" "$(./scripts/5.1-encapsulated-protocol-detection.sh status)"

./scripts/5.1-encapsulated-protocol-detection.sh on > /dev/null
assert_contains "5.1 ON" "ON" "$(./scripts/5.1-encapsulated-protocol-detection.sh status)"

ENCAP_RULES=$(docker exec "$BB" nft list table ip encap_proto_filter 2>/dev/null || true)
assert_contains "5.1 ON: encap_proto_filter table has queue rules" "queue" "$ENCAP_RULES"

./scripts/5.1-encapsulated-protocol-detection.sh off > /dev/null
assert_contains "5.1 OFF after disable" "OFF" "$(./scripts/5.1-encapsulated-protocol-detection.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 15. Packet Manipulation (5.2) ==="
# ---------------------------------------------------------------------------

# Tests both TCP stream reassembly (proxy blocks segmented SNI) and IP fragment drop.

assert_contains "5.2 initially OFF" "OFF" "$(./scripts/5.2-packet-manipulation.sh status)"

./scripts/5.2-packet-manipulation.sh on > /dev/null

# Check proxy is running
assert_contains "5.2 ON: proxy running" "Proxy: running" "$(./scripts/5.2-packet-manipulation.sh status)"

# Check IP fragment drop rule
FRAG_RULES=$(docker exec "$BB" nft list table ip fragmentation_interference 2>/dev/null || true)
assert_contains "5.2 ON: fragment drop rule exists" "frag-off" "$FRAG_RULES"

# TCP stream reassembly test: send a ClientHello SPLIT across two TCP segments
# with a blocked SNI (x.com). The proxy must reassemble and detect the SNI.
SEGMENTED_RESULT=$(docker exec "$CLIENT" python3 -c "
import socket, struct, time
def build_ch(sni):
    sb = sni.encode()
    se = struct.pack('!BH', 0, len(sb)) + sb
    sl = struct.pack('!H', len(se)) + se
    ex = struct.pack('!HH', 0, len(sl)) + sl
    r = b'\x00' * 32
    cb = struct.pack('!H', 0x0303) + r + b'\x00' + struct.pack('!HH', 2, 0x002f) + struct.pack('!BB', 1, 0) + struct.pack('!H', len(ex)) + ex
    hs = struct.pack('!B', 1) + struct.pack('!I', len(cb))[1:] + cb
    return struct.pack('!BHH', 0x16, 0x0301, len(hs)) + hs

hello = build_ch('x.com')
mid = len(hello) // 2
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(('203.0.113.2', 443))
s.send(hello[:mid])
time.sleep(0.1)
s.send(hello[mid:])
try:
    d = s.recv(4096)
    print('FORWARDED' if d else 'CLOSED')
except ConnectionResetError:
    print('RESET')
except socket.timeout:
    print('TIMEOUT')
finally:
    s.close()
" 2>&1)
assert_eq "5.2 ON: segmented blocked SNI is RESET by reassembly proxy" "RESET" "$SEGMENTED_RESULT"

# Same test with an allowed SNI -- should NOT be reset (proxy forwards it)
# We use a real openssl s_client to send a proper segmented ClientHello
ALLOWED_RESULT=$(docker exec "$CLIENT" python3 -c "
import socket, struct, time
def build_ch(sni):
    sb = sni.encode()
    se = struct.pack('!BH', 0, len(sb)) + sb
    sl = struct.pack('!H', len(se)) + se
    ex = struct.pack('!HH', 0, len(sl)) + sl
    r = b'\x00' * 32
    # Use TLS 1.2 cipher ECDHE-RSA-AES128-GCM-SHA256 (0xc02f)
    cb = struct.pack('!H', 0x0303) + r + b'\x00' + struct.pack('!HH', 2, 0xc02f) + struct.pack('!BB', 1, 0) + struct.pack('!H', len(ex)) + ex
    hs = struct.pack('!B', 1) + struct.pack('!I', len(cb))[1:] + cb
    return struct.pack('!BHH', 0x16, 0x0301, len(hs)) + hs

hello = build_ch('allowed.example.com')
mid = len(hello) // 2
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(('203.0.113.2', 443))
s.send(hello[:mid])
time.sleep(0.1)
s.send(hello[mid:])
try:
    d = s.recv(4096)
    # Any response OR clean close means proxy forwarded (not blocked)
    print('NOT_RESET')
except (ConnectionResetError, BrokenPipeError):
    print('RESET')
except socket.timeout:
    print('TIMEOUT')
finally:
    s.close()
" 2>&1)
assert_eq "5.2 ON: segmented allowed SNI is NOT reset" "NOT_RESET" "$ALLOWED_RESULT"

./scripts/5.2-packet-manipulation.sh off > /dev/null
assert_contains "5.2 OFF after disable" "OFF" "$(./scripts/5.2-packet-manipulation.sh status)"

# Verify TLS works normally after proxy is removed (restart TLS server since
# the proxy may have left half-open connections)
restart_tls_server
assert_pass "5.2 OFF: TLS to internet-srv restored" \
    run_c "$CLIENT" "curl -sk --connect-timeout 3 -m 5 https://203.0.113.2/"

# ---------------------------------------------------------------------------
echo ""
echo "=== 16. Active Probing (5.3) ==="
# ---------------------------------------------------------------------------

assert_contains "5.3 initially OFF" "OFF" "$(./scripts/5.3-active-probing.sh status)"

./scripts/5.3-active-probing.sh on > /dev/null
assert_contains "5.3 ON" "ON" "$(./scripts/5.3-active-probing.sh status)"

# Probed IPs should be blocked
probed_ips=$(grep -v '^#' config/backbone/probed_ips.conf | grep -v '^[[:space:]]*$' | awk '{print $1}')
for ip in $probed_ips; do
    assert_fail "5.3 ON: client cannot reach probed IP $ip" \
        run_c "$CLIENT" "ping -c1 -W3 $ip"
done

./scripts/5.3-active-probing.sh off > /dev/null
assert_contains "5.3 OFF after disable" "OFF" "$(./scripts/5.3-active-probing.sh status)"

# Verify probed IP is reachable again (internet-srv has alias 203.0.113.100)
assert_pass "5.3 OFF: probed IP 203.0.113.100 reachable again" \
    run_c "$CLIENT" "ping -c1 -W3 203.0.113.100"

# ---------------------------------------------------------------------------
echo ""
echo "=== 17. Behavioral Pattern Recognition (6.1) ==="
# ---------------------------------------------------------------------------

# Probabilistic filtering -- verify rules are created rather than testing traffic.

assert_contains "6.1 initially OFF" "OFF" "$(./scripts/6.1-behavioral-pattern-recognition.sh status)"

./scripts/6.1-behavioral-pattern-recognition.sh on > /dev/null
assert_contains "6.1 ON" "ON" "$(./scripts/6.1-behavioral-pattern-recognition.sh status)"

BP_RULES=$(docker exec "$BB" nft list table ip behavioral_pattern 2>/dev/null || true)
assert_contains "6.1 ON: random drop rule exists" "numgen random" "$BP_RULES"
assert_contains "6.1 ON: rate limit rule exists" "limit rate" "$BP_RULES"

./scripts/6.1-behavioral-pattern-recognition.sh off > /dev/null
assert_contains "6.1 OFF after disable" "OFF" "$(./scripts/6.1-behavioral-pattern-recognition.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 18. Protocol-Specific Throttling (6.2) ==="
# ---------------------------------------------------------------------------

assert_contains "6.2 initially OFF" "OFF" "$(./scripts/6.2-protocol-specific-throttling.sh status)"

./scripts/6.2-protocol-specific-throttling.sh on > /dev/null
assert_contains "6.2 ON" "ON" "$(./scripts/6.2-protocol-specific-throttling.sh status)"

PT_RULES=$(docker exec "$BB" nft list table ip protocol_throttling 2>/dev/null || true)
assert_contains "6.2 ON: UDP port 443 drop rule exists" "udp dport" "$PT_RULES"

# Start a UDP listener on internet-srv:443 and test that client cannot reach it
run_c "$INTERNET" "bash -c 'nohup python3 -c \"
import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind((\\\"0.0.0.0\\\",443))
while True:
    d,a=s.recvfrom(1024); s.sendto(b\\\"PONG\\\",a)
\" >/dev/null 2>&1 &'"
sleep 0.5

UDP_RESULT=$(docker exec "$CLIENT" python3 -c "
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.settimeout(3)
s.sendto(b'PING',('203.0.113.2',443))
try:
    d,_=s.recvfrom(1024); print(d.decode())
except socket.timeout:
    print('TIMEOUT')
finally:
    s.close()
" 2>&1)
assert_eq "6.2 ON: UDP port 443 traffic is dropped" "TIMEOUT" "$UDP_RESULT"

./scripts/6.2-protocol-specific-throttling.sh off > /dev/null
assert_contains "6.2 OFF after disable" "OFF" "$(./scripts/6.2-protocol-specific-throttling.sh status)"

# Verify UDP works again after disabling
UDP_RESTORED=$(docker exec "$CLIENT" python3 -c "
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.settimeout(3)
s.sendto(b'PING',('203.0.113.2',443))
try:
    d,_=s.recvfrom(1024); print(d.decode())
except socket.timeout:
    print('TIMEOUT')
finally:
    s.close()
" 2>&1)
assert_eq "6.2 OFF: UDP port 443 works again" "PONG" "$UDP_RESTORED"

# Clean up UDP server
run_c "$INTERNET" "pkill -f 'socket.AF_INET,socket.SOCK_DGRAM' 2>/dev/null || true"

# ---------------------------------------------------------------------------
echo ""
echo "=== 19. Dynamic IP Reputation (6.3) ==="
# ---------------------------------------------------------------------------

assert_contains "6.3 initially OFF" "OFF" "$(./scripts/6.3-dynamic-ip-reputation.sh status)"

./scripts/6.3-dynamic-ip-reputation.sh on > /dev/null
assert_contains "6.3 ON" "ON" "$(./scripts/6.3-dynamic-ip-reputation.sh status)"

# Blacklisted IP (203.0.113.10) should be blocked
assert_fail "6.3 ON: blacklisted IP 203.0.113.10 is blocked" \
    run_c "$CLIENT" "ping -c1 -W3 203.0.113.10"

# Whitelisted IP (203.0.113.1 = backbone itself) should be reachable
assert_pass "6.3 ON: whitelisted IP 203.0.113.1 is reachable" \
    run_c "$CLIENT" "ping -c1 -W3 203.0.113.1"

./scripts/6.3-dynamic-ip-reputation.sh off > /dev/null
assert_contains "6.3 OFF after disable" "OFF" "$(./scripts/6.3-dynamic-ip-reputation.sh status)"

# Verify previously blacklisted IP is reachable again (internet-srv has alias 203.0.113.10)
assert_pass "6.3 OFF: blacklisted IP 203.0.113.10 reachable again" \
    run_c "$CLIENT" "ping -c1 -W3 203.0.113.10"

# ---------------------------------------------------------------------------
echo ""
echo "=== 20. Selective Bandwidth Throttling (6.4) ==="
# ---------------------------------------------------------------------------

assert_contains "6.4 initially OFF" "OFF" "$(./scripts/6.4-selective-bandwidth-throttling.sh status)"

./scripts/6.4-selective-bandwidth-throttling.sh on > /dev/null
assert_contains "6.4 ON" "ON" "$(./scripts/6.4-selective-bandwidth-throttling.sh status)"

TBF_RULES=$(docker exec "$BB" tc qdisc show dev "$BB_INT_IF" 2>/dev/null || true)
assert_contains "6.4 ON: TBF qdisc active on $BB_INT_IF" "tbf" "$TBF_RULES"

./scripts/6.4-selective-bandwidth-throttling.sh off > /dev/null
assert_contains "6.4 OFF after disable" "OFF" "$(./scripts/6.4-selective-bandwidth-throttling.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 21. Degradation-Based Filtering (6.5) ==="
# ---------------------------------------------------------------------------

assert_contains "6.5 initially OFF" "OFF" "$(./scripts/6.5-degradation-based-filtering.sh status)"

./scripts/6.5-degradation-based-filtering.sh on > /dev/null
assert_contains "6.5 ON" "ON" "$(./scripts/6.5-degradation-based-filtering.sh status)"

NETEM_RULES=$(docker exec "$BB" tc qdisc show dev "$BB_INT_IF" 2>/dev/null || true)
assert_contains "6.5 ON: netem qdisc active on $BB_INT_IF" "netem" "$NETEM_RULES"

./scripts/6.5-degradation-based-filtering.sh off > /dev/null
assert_contains "6.5 OFF after disable" "OFF" "$(./scripts/6.5-degradation-based-filtering.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 22. Kill Switch (7.1) ==="
# ---------------------------------------------------------------------------

assert_contains "7.1 initially OFF" "Internet is ACTIVE" "$(./scripts/7.1-kill-switch.sh status)"

./scripts/7.1-kill-switch.sh on > /dev/null
assert_contains "7.1 ON" "Internet is SHUT DOWN" "$(./scripts/7.1-kill-switch.sh status)"

assert_fail "7.1 ON: client cannot reach real internet (1.1.1.1)" \
    run_c "$CLIENT" "ping -c1 -W2 1.1.1.1"

assert_fail "7.1 ON: client cannot reach internet-srv (203.0.113.2)" \
    run_c "$CLIENT" "ping -c1 -W2 203.0.113.2"

if [ "$TOPOLOGY" = "realistic" ]; then
    # Realistic: kill switch drops backbone forwarding only; intranet stays up
    # (domestic NIN traffic routes via tehran-ix, bypassing backbone)
    assert_pass "7.1 ON: intranet still reachable (realistic: NIN stays up)" \
        run_c "$CLIENT" "ping -c1 -W2 10.10.10.2"
else
    # Simple: IXP-ISP link severed, everything blocked including intranet
    assert_fail "7.1 ON: client cannot reach intranet (10.10.10.2)" \
        run_c "$CLIENT" "ping -c1 -W2 10.10.10.2"
fi

./scripts/7.1-kill-switch.sh off > /dev/null
assert_contains "7.1 OFF after disable" "Internet is ACTIVE" "$(./scripts/7.1-kill-switch.sh status)"

assert_pass "7.1 OFF: client can reach real internet again (1.1.1.1)" \
    run_c "$CLIENT" "ping -c1 -W3 1.1.1.1"

# ---------------------------------------------------------------------------
echo ""
echo "=== 23. Tiered Access (7.2) ==="
# ---------------------------------------------------------------------------

assert_contains "7.2 initially OFF" "INACTIVE" "$(./scripts/7.2-tiered-access.sh status)"

# Enable IP blocking first, then tiered access
./scripts/3.1-ip-blocking.sh on > /dev/null

# Verify the blocked IP is actually blocked
assert_fail "7.2 setup: blocked IP 172.66.0.227 is blocked" \
    run_c "$CLIENT" "ping -c1 -W3 172.66.0.227"

./scripts/7.2-tiered-access.sh on > /dev/null
assert_contains "7.2 ON" "ACTIVE" "$(./scripts/7.2-tiered-access.sh status)"

# Verify privileged IPs in the nftables set
PRIV_SET=$(docker exec "$BB" nft list set ip global_whitelist privileged_ips 2>/dev/null || true)
assert_contains "7.2 ON: privileged set contains 10.0.1.100" "10.0.1.100" "$PRIV_SET"

# Verify the mark rule exists in the ip_blocking table (injected exemption)
IP_BLOCK_RULES=$(docker exec "$BB" nft list chain ip ip_blocking forward 2>/dev/null || true)
assert_contains "7.2 ON: exemption injected into ip_blocking" "mark" "$IP_BLOCK_RULES"

# TRAFFIC TEST: The client IP 10.0.1.100 is in the privileged list.
# With 3.1 ON, 172.66.0.227 is blocked. But privileged IP should bypass.
# We configure the client to use 10.0.1.100 as a source address and test.
# Since the client's actual IP is 10.0.1.2, we add 10.0.1.100 as an alias.
run_c "$CLIENT" "ip addr add 10.0.1.100/24 dev eth1 2>/dev/null || true"

# Client from privileged IP should bypass the IP block
assert_pass "7.2 ON: privileged IP bypasses IP blocking (ping 172.66.0.227)" \
    run_c "$CLIENT" "ping -c1 -W3 -I 10.0.1.100 172.66.0.227"

# Non-privileged IP (the default 10.0.1.2) should still be blocked
assert_fail "7.2 ON: non-privileged IP still blocked (ping 172.66.0.227)" \
    run_c "$CLIENT" "ping -c1 -W3 172.66.0.227"

# Clean up alias
run_c "$CLIENT" "ip addr del 10.0.1.100/24 dev eth1 2>/dev/null || true"

./scripts/7.2-tiered-access.sh off > /dev/null
./scripts/3.1-ip-blocking.sh off > /dev/null
assert_contains "7.2 OFF after disable" "INACTIVE" "$(./scripts/7.2-tiered-access.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 24. Protocol Whitelisting (7.3) ==="
# ---------------------------------------------------------------------------

assert_contains "7.3 initially OFF" "OFF" "$(./scripts/7.3-protocol-whitelisting.sh status)"

./scripts/7.3-protocol-whitelisting.sh on > /dev/null
assert_contains "7.3 ON" "ON" "$(./scripts/7.3-protocol-whitelisting.sh status)"

# Allowed: ICMP ping should work
assert_pass "7.3 ON: ICMP ping to internet-srv works (whitelisted)" \
    run_c "$CLIENT" "ping -c1 -W3 203.0.113.2"

# Allowed: HTTP (port 80) should work
assert_pass "7.3 ON: HTTP to internet-srv works (whitelisted)" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 http://203.0.113.2/"

# Blocked: non-whitelisted port (e.g. 8080) should fail
assert_fail "7.3 ON: port 8080 is blocked (not whitelisted)" \
    run_c "$CLIENT" "curl -s --connect-timeout 3 -m 5 http://203.0.113.2:8080/"

./scripts/7.3-protocol-whitelisting.sh off > /dev/null
assert_contains "7.3 OFF after disable" "OFF" "$(./scripts/7.3-protocol-whitelisting.sh status)"

# ---------------------------------------------------------------------------
echo ""
echo "=== 25. Tiered Access + Protocol Whitelisting integration (7.2 + 7.3) ==="
# ---------------------------------------------------------------------------

# Enable 7.3 (default-deny) first, then 7.2 (tiered access)
./scripts/7.3-protocol-whitelisting.sh on > /dev/null
./scripts/7.2-tiered-access.sh on > /dev/null

# Verify the mark exemption was injected into protocol_whitelisting
PW_RULES=$(docker exec "$BB" nft list chain ip protocol_whitelisting forward 2>/dev/null || true)
assert_contains "7.2+7.3: mark exemption injected into protocol_whitelisting" "mark" "$PW_RULES"

./scripts/7.2-tiered-access.sh off > /dev/null
./scripts/7.3-protocol-whitelisting.sh off > /dev/null

# Also test reverse order: 7.2 first, then 7.3
./scripts/7.2-tiered-access.sh on > /dev/null
./scripts/7.3-protocol-whitelisting.sh on > /dev/null

PW_RULES2=$(docker exec "$BB" nft list chain ip protocol_whitelisting forward 2>/dev/null || true)
assert_contains "7.3+7.2 (reverse): mark exemption in protocol_whitelisting" "mark" "$PW_RULES2"

./scripts/7.3-protocol-whitelisting.sh off > /dev/null
./scripts/7.2-tiered-access.sh off > /dev/null

# ---------------------------------------------------------------------------
echo ""
echo "=== 26. Idempotency (double on/off) ==="
# ---------------------------------------------------------------------------

# Enabling a mechanism twice should not break it or duplicate rules.

./scripts/3.1-ip-blocking.sh on > /dev/null
./scripts/3.1-ip-blocking.sh on > /dev/null
assert_contains "3.1 idempotent: ON twice -> still ON" "ON" "$(./scripts/3.1-ip-blocking.sh status)"
assert_fail "3.1 idempotent: still blocks after double on" \
    run_c "$CLIENT" "ping -c1 -W3 172.66.0.227"
./scripts/3.1-ip-blocking.sh off > /dev/null
./scripts/3.1-ip-blocking.sh off > /dev/null
assert_contains "3.1 idempotent: OFF twice -> still OFF" "OFF" "$(./scripts/3.1-ip-blocking.sh status)"
assert_pass "3.1 idempotent: reachable after double off" \
    run_c "$CLIENT" "ping -c1 -W3 172.66.0.227"

./scripts/5.2-packet-manipulation.sh on > /dev/null
./scripts/5.2-packet-manipulation.sh on > /dev/null
assert_contains "5.2 idempotent: ON twice -> proxy running" "Proxy: running" "$(./scripts/5.2-packet-manipulation.sh status)"
./scripts/5.2-packet-manipulation.sh off > /dev/null
./scripts/5.2-packet-manipulation.sh off > /dev/null
assert_contains "5.2 idempotent: OFF twice -> OFF" "OFF" "$(./scripts/5.2-packet-manipulation.sh status)"

# Restart TLS server after proxy cleanup
restart_tls_server

./scripts/7.1-kill-switch.sh on > /dev/null
./scripts/7.1-kill-switch.sh on > /dev/null
assert_fail "7.1 idempotent: still blocks after double on" \
    run_c "$CLIENT" "ping -c1 -W2 1.1.1.1"
./scripts/7.1-kill-switch.sh off > /dev/null
./scripts/7.1-kill-switch.sh off > /dev/null
assert_pass "7.1 idempotent: reachable after double off" \
    run_c "$CLIENT" "ping -c1 -W3 1.1.1.1"

# ===========================================================================
echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================="

exit "$FAIL"
