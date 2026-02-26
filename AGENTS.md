# Simulation Agents

This lab simulates a network environment to test internet filtering scenarios. The topology consists of four distinct agents (containers), each playing a specific role in the connection flow.

i'm not insisting to make this lab a complete 1-1 mapping of the real world, as it is impossible and not needed, but i want to make the main concepts as close to the real world as possible.

## real world setup

- we have some cables coming into iran from outside of iran
  - **submarine cables**: e.g. the **FALCON** cable lands on the southern coast at Bandar Abbas (Indian Ocean), providing connectivity toward the Gulf states and beyond. simulated by `gw-falcon` in the realistic topology.
  - **terrestrial cables**: e.g. the **EPEG** cable enters from Turkey/Azerbaijan through the northwest border near Tabriz. simulated by `gw-epeg` in the realistic topology.
  - these cable landing points are the physical entry of international traffic into Iran. they connect directly to the TIC backbone at regional nodes.
- TIC backbone network: the first point of contact for all international traffic is **TIC (Telecommunications Infrastructure Company, AS12880)** -- Iran's primary transit provider and the national chokepoint -- alongside IRGC-controlled infrastructure. simulated by `tic-tehran` (and `tic-south`, `tic-west`, `tic-east` in the realistic topology).
  - there are several TIC backbone nodes which are the first point of contact for traffic entering Iran -- one per major region (Tehran, south/Isfahan, west/Tabriz, east/Mashhad)
  - these nodes are controlled by TIC, IRGC, and related government entities
  - these devices are probably some advanced and expensive and complex devices
  - regarding who is providing these devices and technologies to the terroristic regime of Iran:
    - according to an ARTICLE 19 report (February 2026) and The Guardian investigation, Chinese companies are the primary suppliers: Huawei and ZTE provide DPI and internet-filtering equipment, while Hikvision and Tiandy supply surveillance and facial recognition systems (the same technologies used against Uyghurs in China). There are also smaller, less-known Chinese companies providing tools with "alarming" capabilities that researchers have not yet fully analyzed.
    - Russia has also been a key partner: according to United24 Media and Agenstvo Novosti reports, Russian company Protei helped Iranian mobile operators integrate DPI into their interception systems. Russia also provided electronic warfare systems (tested in Ukraine) for jamming Starlink satellite internet signals, and helped build the multi-layered architecture used in the January 2026 shutdown -- one of the most sophisticated internet shutdowns in history.
    - both China and Iran promote "cyber sovereignty" at the UN level -- the idea that a state has absolute control over the internet within its borders -- in an attempt to legitimize internet shutdowns and digital repression as "sovereign rights."
    - if any US/EU/AUS/JP/KOREA/... companies are involved, they are probably circumventing international sanctions.
  - TIC backbone nodes interconnect via direct private fiber links or via TIC's own AS12880 BGP peering -- **NOT through IXPs**. see the transit vs peering section below.
- IXP network: after the TIC backbone layer there are peering points called IXP (Internet Exchange Point) or public site or pubsite or public peering or ... simulated by `tehran-ix` (and `isfahan-ix`, `tabriz-ix`, `mashhad-ix` in the realistic topology).
  - they sit after the TIC backbone layer; TIC backbone nodes connect **to** IXPs as participants (not as a transit path between backbone nodes)
  - IXPs enable east-west peering between ISPs and domestic content providers -- they do not carry north-south (international transit) traffic on their own
  - the IXP sites are mostly deployed near big cities: Tehran, Mashhad, Tabriz, Isfahan, and others
- wholesale/transit aggregation: between the IXPs and retail ISPs there is often a **wholesale** layer. in Iran, **TCI (Telecommunications Company of Iran, AS58224)** -- the state-owned fixed-line incumbent -- acts as the wholesale carrier that aggregates retail ISPs and mobile operators in each region. simulated by `tci`, `tci-south`, `tci-west`, `tci-east` in the realistic topology. note: TCI (retail/wholesale incumbent) is distinct from TIC (international backbone/transit).
- ISP networks: the retail layer serving end users. simulated by `isp-shatel`, `isp-south`, `isp-west`, `isp-east`.
  - as an example of ISP networks: Shatel, IranCell, MCI/HamrahAvval, HiWeb, MobenNet, Mokhaberat, ...
  - each ISP site is connected to several end users (home users, business users, ...)
  - each brand might have their own filtering infrastructure (GFW)
  - END USERS are connected to the ISP sites, through wired or wireless links
- mobile carriers: a specialized ISP type that applies **CGNAT** (carrier-grade NAT) to subscriber traffic. simulated by `mob-irancell`, `mob-mci`, `mob-mci-west`, `mob-mci-east` in the realistic topology. CGNAT means the internet sees the carrier's shared IP, not the subscriber's actual address.
- NIN domestic content: servers directly connected to IXPs (not through TIC backbone). these survive international shutdowns because they never need TIC for local reachability. simulated by `aparat-server`.

## so we would have this setup in abstract:

1. internet
2. border gateways (cable landing points: FALCON, EPEG) → `gw-falcon`, `gw-epeg` (realistic only)
3. TIC backbone (AS12880) — transit/filtering chokepoint → `tic-tehran` (+`tic-south`, `tic-west`, `tic-east` in realistic) [TRANSIT PLANE]
4. IXPs (Tehran IX, Isfahan IX, Tabriz IX, Mashhad IX) → `tehran-ix` (+`isfahan-ix`, `tabriz-ix`, `mashhad-ix` in realistic) [TRANSIT/PEERING handoff]
5. wholesale/transit aggregation (TCI, AS58224) → `tci` (+`tci-south`, `tci-west`, `tci-east` in realistic)
6. ISPs (Shatel, Mokhaberat, ...) → `isp-shatel` (+`isp-south`, `isp-west`, `isp-east` in realistic) [PEERING PLANE]
7. mobile carriers (IranCell, MCI, ...) → `mob-irancell`, `mob-mci`, etc. (realistic) [MOBILE SUBSCRIBER PLANE]
8. end users → `iran-client`, `client-android` (simple), `client-tehran/south/west/east/mobile` (realistic)
9. NIN domestic content (directly on IXP, no TIC path) → `aparat-server` [PEERING PLANE]

the simple topology (`topology.clab.yml`) collapses layers 2, 5 and most of 7 for lightweight testing, keeping the key structural relationships intact. the realistic topology (`topology-realistic.clab.yml`) models all layers across 4 regions.

## transit vs peering: north-south and east-west traffic

understanding the difference between transit and peering is essential for understanding how Iranian internet traffic flows and why some services survive shutdowns while others do not.

### transit (north-south traffic)

**transit** means you pay an upstream provider to carry your traffic to the rest of the internet. it is a commercial relationship: you buy access to the full global routing table. in Iran, **TIC (Telecommunications Infrastructure Company, AS12880)** is the primary transit provider. when an Iranian ISP wants to reach YouTube, the traffic goes:

```
iran-client -> isp-shatel -> tci -> tehran-ix -> tic-tehran -> gw-falcon/epeg -> internet
```
(simple topology collapses tci and the border gateways: `iran-client -> isp-shatel -> tehran-ix -> tic-tehran -> internet-srv`)

this is "north-south" traffic: it crosses the national border. TIC is the chokepoint -- this is where filtering, DPI, and bandwidth throttling are applied. if TIC cuts the international link, all transit traffic dies.

### peering (east-west traffic)

**peering** means two networks agree to exchange traffic directly with each other for free (or at low cost), without paying a transit provider. this only works for traffic that stays between the two peering parties -- it does not give you access to the rest of the internet. in Iran, **tehran-ix** (Tehran Internet Exchange) is the main facility where domestic ISPs and content providers peer with each other. when an Iranian user reaches a domestic service like Aparat or Rubika, the traffic can flow:

```
iran-client -> isp-shatel -> tci -> tehran-ix -> aparat-server (domestic content)
```
(simple topology: `iran-client -> isp-shatel -> tehran-ix -> aparat-server`)

this is "east-west" traffic: it stays inside Iran and never touches TIC's international backbone. because it bypasses TIC entirely, it also bypasses TIC's filtering and international link dependencies.

### why this matters during shutdowns

when the regime cuts international internet access (the "kill switch"), they sever TIC's upstream links. this kills all north-south (transit) traffic to the global internet. however, east-west (peering) traffic between domestic networks through tehran-ix continues to work -- which is why Iranian banking, domestic social media (Soroush, Rubika), and local services remain reachable during full internet shutdowns.

this is the key insight: **a domestic content server connected directly to an IXP survives international shutdowns because it never needed TIC to reach local users.**

### analogy

think of transit like buying a multi-hop airline ticket through a hub: you pay, the journey is long, and if the main hub shuts down, you are stuck. peering is like a direct shuttle between two nearby cities: it is free between the parties, faster, and completely independent of the main airline hub.

### CGNAT: The Mobile Network Fortress

**CGNAT (Carrier-Grade NAT)** is a large-scale network address translation method used by mobile carriers (like MTN Irancell and MCI) to handle IPv4 address exhaustion. While standard home routers perform NAT for a few devices, CGNAT does this for thousands of mobile subscribers simultaneously.

#### How it works:
1.  **IP Sharing:** Thousands of subscribers are assigned private, non-routable internal IPs (e.g., in the `10.x.x.x` range). When they access the internet, their traffic is mapped to a single public IP address shared by the entire pool.
2.  **Stateful Isolation:** The carrier's gateway maintains a state table of outgoing connections. It only allows incoming traffic if it matches an existing entry in this table (i.e., it's a response to a subscriber's request).
3.  **Inbound Blocking:** By default, any "unsolicited" inbound traffic (a new connection initiated from the internet toward a subscriber) is dropped. This means a mobile phone on a CGNAT network has no "reachable" public presence.

#### Impact on VPNs and Circumvention:
-   **Inbound Restriction:** You cannot host a VPN server directly on a mobile connection. Since the carrier blocks unsolicited inbound packets, a client from the internet cannot "find" or "connect" to a mobile-hosted server.
-   **Peer-to-Peer (P2P) Challenges:** Protocols that rely on direct device-to-device communication (like ZeroTier, Tailscale, or certain gaming protocols) often struggle or fail behind CGNAT because they cannot establish a direct "hole-punch" through the carrier's strict NAT layer.
-   **Identification vs. Anonymity:** While CGNAT makes it harder for the GFW to identify a *specific* user by IP alone (since many share one), it makes it easier to block *thousands* of users at once. If the GFW identifies a single "suspicious" VPN tunnel exiting from a carrier's shared IP, it might decide to throttle or block that entire IP, affecting every other innocent subscriber sharing it.
-   **Session Timeouts:** CGNAT gateways often have aggressive timeout policies for UDP and TCP sessions to save memory. This can cause "zombie" VPN connections where the client thinks it's connected, but the carrier has already closed the NAT mapping, requiring frequent keep-alive packets that increase the VPN's battery consumption and traffic signature.

### how this maps to the realistic topology

in `topology-realistic.clab.yml`:
- **TRANSIT PLANE**: links between `tic-tehran` (backbone) and the outside world -- north-south paid transit. filtering and DPI live here.
- **PEERING PLANE**: links between `tehran-ix` and ISPs/domestic servers -- east-west free exchange. no filtering on this plane.
- **TRANSIT/PEERING handoff**: the link between `tic-tehran` and `tehran-ix` is where the two planes meet. `tehran-ix` acts as a distribution node: it receives international traffic from TIC and distributes it to ISPs, and it also provides a peering fabric for domestic-only traffic that bypasses TIC entirely.
- **`aparat-server`**: a domestic content server (representing services like Aparat or Rubika) connected directly to `tehran-ix`. it has no path through `tic-tehran`, so it is reachable during international shutdowns.
- **`mob-irancell`**: the mobile carrier node sits on both the peering plane (domestic) and applies CGNAT (carrier-grade NAT) for subscriber traffic before it exits upstream.

### clarification: how backbone nodes interconnect

the TIC backbone nodes are **not** connected to each other through IXP. backbone-to-backbone interconnect happens either via direct fiber (private backbone links) or via the international transit peering between TIC's own AS and upstream providers. IXPs are strictly for peering between different autonomous systems (ISPs, CDNs, content providers) -- they are not part of the backbone's own internal routing. the backbone connects **to** IXPs as a participant, not as a transit path between backbone nodes.

## the ways the filtering is implemented:
the filtering is implemented via different ways:

1. **DNS-Layer Filtering** (Primarily ISP Layer)
   - **1.1 DNS Hijacking and Poisoning:** The most common initial method where the ISP's DNS server returns fake information. (ISP Layer)
     - The DNS server returns the IP address of an alternative website like `peyvandha.ir` (which is not the case anymore as of 2022). For example, it will return `peyvandha.ir` or `10.10.3.5` (just an example, i'm not sure if this is the real IP address of `peyvandha.ir`) although the `peyvandha.ir` and its IP addresss are not available anymore from the start of 2022. The ips related to `peyvandha.ir` were `10.10.34.34`, `10.10.34.35`, and `10.10.34.36`.
     - Or the DNS server returns a fake IP address that is not reachable, leading the client to get a connection timeout.
     - This is usually implemented in the ISP layer because it is standard for ISPs to have their own DNS servers for their customers.
   - **1.2 DoH and DoT Blocking:** Since DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) can bypass traditional ISP poisoning by encrypting the query, the TIC backbone layer intervenes. (TIC backbone layer / `tic-tehran`)
     - Suppose a user tries to use a secure resolver to bypass the ISP's poison. The GFW actively blocks the IP addresses of known public DoH/DoT providers like Cloudflare (`1.1.1.1`), Google (`8.8.8.8`), and Quad9. This forces the client to fall back to the ISP's monitored DNS servers.

2. **HTTP Host Header Inspection and Blockpage Injection** (TIC backbone layer / `tic-tehran`)
   - **2.1 HTTP Host and URL Keyword Filtering:** For plaintext HTTP traffic (which is still significant in Iran), the GFW inspects the `Host` header and URL keywords in HTTP requests at the backbone layer.
     - If a blocked domain is detected in the `Host` header, the GFW injects a forged HTTP response -- either a blockpage (e.g., an HTTP 302 redirect to a government-controlled page, like the former `peyvandha.ir`) or a TCP RST to kill the connection.
     - This is distinct from DNS poisoning: even if the user bypasses DNS filtering and connects to the correct IP, the GFW can still detect the blocked domain in the plaintext HTTP `Host` header and block the request.
     - The IRBlock study (USENIX Security 2025) found 6.8 million IPs affected by HTTP blockpage injection, showing this is still a widely-used technique despite the growth of HTTPS.
     - This technique is only effective against unencrypted HTTP traffic; HTTPS encrypts the Host header, which is why the regime also relies on SNI inspection (section 4.1 below) for encrypted traffic.

3. **IP and Routing Layer Filtering** (TIC backbone layer / `tic-tehran`)
   - **3.1 Individual and Range (CIDR) Blocking:** Even if the user manages to bypass DNS filtering (e.g., by using a custom DNS resolver or hardcoding the IP address), the backbone can drop all packets destined for specific IPs or ranges.
     - For example, `x.com` is hosted on Cloudflare at `172.66.0.227`. Even if the user knows this IP and tries to connect directly, the backbone will drop the traffic.
     - In practice, the regime often blocks entire CIDR ranges (e.g., Cloudflare IP ranges) rather than individual IPs, which causes collateral damage to unrelated websites hosted on the same infrastructure.
     - This is done at the TIC backbone layer (`tic-tehran`), not the ISP or IXP, because TIC is the national chokepoint where all international transit traffic passes. IXP is just a peering/routing layer; it doesn't inspect or filter traffic. Maintaining centralized IP blacklists is TIC's responsibility at the national level, and ISPs generally don't maintain their own blacklists.
     - This serves as the second line of defense and is also used to block known VPN server IPs, Tor relays, and proxy servers.
   - **3.2 BGP Hijacking and Blackholing:** BGP (Border Gateway Protocol) is the protocol that "glues" the world's autonomous systems together. The regime manipulates this protocol to "kidnap" or "swallow" traffic before it even reaches its intended destination.
     - **Mechanism (BGP Hijacking):** The national backbone (TIC - AS12880) can announce a "more specific" route (a smaller IP prefix) for an international service than what the actual owner (e.g., Google or Cloudflare) is announcing. Since internet routers always prefer the most specific path, traffic from around the world (or within the region) is sucked into Iran's network.
     - **Mechanism (Blackholing):** Once the traffic is diverted into the Iranian backbone, it is simply "dropped" (sent to a `null` interface). This effectively makes the service unreachable globally or regionally, depending on how far the fake BGP announcement spreads.
     - **Scenario 1: Global Blackholing (The "Telegram" Case):** Suppose Telegram uses `149.154.160.0/20`. The Iranian backbone could announce `149.154.167.0/24`. Routers worldwide that see both will prefer the `/24` (the more specific one). If Iran announces this to its international peers, traffic intended for that Telegram segment enters Iran and is discarded, causing a partial global outage for the service.
     - **Scenario 2: Internal/Regional Redirection:** Instead of a global hijack, the regime can perform an internal hijack where only ISPs inside Iran are forced to see the fake route. This ensures that 100% of domestic traffic for a target is "sucked" into a specific backbone node for inspection, bypassing any potential bypass routes the ISP might have.
     - **Scenario 3: Redirection to "Scrubbing Centers" (DPI Clusters):** Instead of dropping the traffic (blackholing), they can divert it to specialized "Scrubbing Centers" or DPI clusters. Traffic for `x.com` is hijacked, sent through a Huawei or Protei DPI box for SNI/content inspection, and only then (if allowed) forwarded to the real destination. This ensures 100% of traffic for a target is inspected, even if it uses non-standard ports or tries to hide from the standard gateway.
   - **3.3 IPv6 Systematic Filtering:** As IPv6 adoption increases, the GFW has implemented identical filtering rules for IPv6 traffic.
     - In some cases, IPv6 is completely disabled at the backbone level to close potential "backdoors" that users might exploit to bypass IPv4-only filtering rules.

4. **Transport Layer and Encryption Handshake Filtering** (TIC backbone layer / `tic-tehran`)
   - **4.1 SNI (Server Name Indication) Discovery:** Suppose you managed to circumvent DNS filtering (e.g., you are trying to visit `x.com`, and as it's filtered, you try to get the IP address of `x.com` using cloudflare dns or google dns or ...).
     - Suppose now you have the IP address of `x.com` -> `a.b.c.d`.
     - During the encrypted HTTPS/TLS connection, after the TCP handshake, the client initiates the SSL Handshake. This handshake contains the SNI (Server Name Indication) field, which holds the domain or hostname of the server (e.g., `x.com`) in cleartext.
     - By discovering this SNI, the GFW will completely drop the connection.
     - This is mostly done at the backbone layer because implementing this requires expensive and complex DPI devices that ISPs typically do not have.
   - **4.2 TLS Fingerprinting and Session Behavioral Analysis (JA3/JA3S/JA4):** Modern GFW systems can identify specific VPN clients or unauthorized browsers by the unique "fingerprint" of their TLS handshake pattern.
     - Even if the SNI is hidden or encrypted (e.g., using ECH), the handshake behavior (the set of supported ciphers, extensions, etc.) is often unique enough to allow the GFW to identify and block unauthorized tools while allowing standard browser traffic.
     - Beyond the static handshake fingerprint, the GFW also performs **TLS session behavioral analysis**: it evaluates whether an encrypted session "behaves" like normal browser traffic. Key signals include the TLS ClientHello extension order and cipher suite selection (JA3/JA4 fingerprint), the inter-arrival time between packets, the session duration and lifetime pattern, and whether the traffic volume and timing resemble human browsing or a persistent tunnel.
     - Field testing (Bahman 1404 / early 2026) has confirmed that **all TLS-based proxy transports** -- including WebSocket+TLS, TCP+TLS, gRPC+TLS, Trojan, and Reality (both TCP and gRPC modes) -- are either immediately blocked or actively disrupted after approximately 10 minutes, regardless of the specific transport, SNI, certificate, port, or client platform. This behavior was consistent across multiple ISPs, ports (443, 8443, 2053, 2083, etc.), and client platforms (Windows 10/11, Android).
     - In contrast, **non-TLS transports** (plain WebSocket, plain TCP, HTTP Upgrade, xHTTP without TLS) remained stable in the same testing period, with no systematic resets or active disruptions. This confirms that the activation of TLS itself is the primary trigger for the GFW's detection and disruption mechanisms, not the specific transport protocol or configuration details.
     - This means that simply changing the proxy protocol or adding obfuscation layers on top of TLS does not help -- if the underlying TLS session fingerprint does not closely mimic a real browser session in terms of both its handshake and its ongoing behavioral pattern, it will be detected and disrupted.
   - **4.3 TCP RST Injection and Active Stream Interference:** The GFW uses two main active interference techniques to disrupt connections:
     - **TCP RST Injection:** When the GFW detects a blocked SNI or HTTP Host header, it sends forged TCP RST (reset) packets to both the client and the server, causing both sides to immediately tear down the connection. This is the primary enforcement mechanism for SNI-based and HTTP-based blocking -- the GFW doesn't just passively drop packets, it actively kills the connection by spoofing reset signals.
     - **Garbage Data Injection:** During an active connection, the GFW may also inject "garbage" data or invalid packets into the TCP stream. Suppose a user is using an obfuscated protocol like Shadowsocks. The GFW injects a small amount of invalid data. While a standard browser might fail gracefully, this tactic is specifically designed to break the state machines of obfuscation tools that expect a very specific protocol structure, causing them to fail or expose their signature.

5. **Deep Packet Inspection (DPI) and Protocol Analysis** (TIC backbone layer / `tic-tehran`)
   - **5.1 Encapsulated Protocol Detection:** Sometimes the appearance of the packet is not suspicious to the naked eye (it does not contain SNI, etc.), so the GFW uses DPI to inspect the internal layers of the packet.
     - They attempt to find encapsulated protocols like VMess, VLess, or other detectable VPN and proxy signatures.
     - If any of these are found, the packet is dropped. This is performed at the backbone layer as ISPs usually don't implement this method because it's expensive and complex and they don't have the resources to do it (at least up to our knowledge).
   - **5.2 Packet Manipulation and Fragmentation Interference:** This mechanism has two distinct aspects -- a bypass technique used by anti-filtering tools, and the GFW's countermeasures against it:
     - **The bypass technique (TCP segmentation / TLS record fragmentation):** Anti-filtering tools like GoodbyeDPI, zapret, and MahsaNG ("HTTPS Fragment") split the TLS ClientHello message into multiple small **TCP segments** so that the SNI field is spread across separate packets. Since many DPI systems inspect individual packets rather than fully reassembling the TCP stream, the DPI cannot see the complete domain name in any single packet buffer. Crucially, this is **TCP segmentation** (application/transport layer), not **IP fragmentation** (network layer) -- each TCP segment is sent as a complete, unfragmented IP packet. TLS record fragmentation is a related technique that splits the ClientHello at the TLS record layer, achieving a similar effect without requiring root privileges. These techniques have been shown to bypass SNI-based censorship in both China and Iran (Paderborn University, 2023/2025; FOCI 2020).
     - **The GFW's countermeasures:** The primary countermeasure is **TCP stream reassembly** -- modern DPI systems (like those deployed by Huawei/ZTE) buffer and reassemble the full TCP stream before inspecting it, defeating simple segmentation. Additionally, the GFW may flag connections that begin with unusually small TCP segments as suspicious (behavioral detection). As a separate, blunter measure, the backbone may **drop IP-fragmented packets** entirely as a general security policy, which disrupts protocols or tools that rely on IP-level fragmentation. The combination of stream reassembly + behavioral detection + fragment dropping makes pure segmentation-based bypasses increasingly unreliable without additional techniques (fake packets, TTL manipulation, desynchronization).
     - **References:** Paderborn University "Circumventing the GFW with TLS Record Fragmentation" (2023); "Transport Layer Obscurity: Circumventing SNI Censorship on the TLS-Layer" (CensorBib 2025); University of Maryland "Detecting and Evading Censorship-in-Depth" (FOCI 2020); zapret documentation on TCP desynchronization; GoodbyeDPI packet fragmentation techniques.
   - **5.3 Active Probing and Server Fingerprinting:** The GFW doesn't only passively inspect traffic -- it also actively probes suspected VPN/proxy servers.
     - When the DPI system detects suspicious traffic patterns (e.g., a connection that looks like it might be Shadowsocks, Tor, or an obfuscated proxy), it initiates its own connection from government-controlled probing clients to the destination server.
     - These probing clients attempt to "handshake" with the suspected server using known VPN/proxy protocols. If the server responds in a way that confirms it is running a VPN or proxy service, the server's IP is immediately blacklisted.
     - This was a major technique from approximately 2022-2024. By early 2024, upgrades to Iran's DPI infrastructure reduced reliance on active probing (since passive DPI became accurate enough), but it remains part of the arsenal and can be reactivated.
     - This technique is particularly effective against protocols like Shadowsocks and Tor bridges, where the server must respond to protocol-specific handshakes that the prober can trigger.

6. **Behavioral, Statistical, and Quality-of-Service Filtering** (TIC backbone layer / `tic-tehran`)
   - **6.1 Behavioral Pattern Recognition and Statistics:** The GFW matches the traffic patterns (packet size, frequency, and entropy) against those it doesn't like.
     - Based on these statistical models or machine learning, it decides to drop the traffic, lower the quality of the traffic, or lower the bandwidth.
     - This model is mostly done in the backbone layer; ISPs usually do not implement this because it's expensive and complex and they don't have the resources (at least up to our knowledge).
   - **6.2 Protocol-Specific Throttling (UDP/QUIC):** Many modern protocols (HTTP/3, QUIC, WireGuard) rely on UDP.
     - Suppose a user tries to connect via a high-speed QUIC-based VPN. The backbone layer often heavily throttles or completely blocks UDP traffic on port 443. This forces the client to fall back to the TCP protocol, which is much easier for the GFW to inspect and manipulate.
   - **6.3 Dynamic IP Reputation System (Whitelist/Graylist/Blacklist):** The GFW maintains a dynamic reputation system for destination IP addresses, distinct from the static IP blacklists in section 3.1.
     - **Whitelist:** IPs with no recent suspicious (VPN/proxy) activity -- full speed, no interference.
     - **Graylist:** IPs flagged as suspicious (e.g., receiving encrypted traffic with high entropy, or traffic patterns matching known VPN signatures) -- these are throttled, intermittently blocked, or subjected to more aggressive DPI.
     - **Blacklist:** IPs confirmed as VPN/proxy servers (via active probing or sustained suspicious traffic) -- fully blocked.
     - A new VPN server IP typically starts as whitelisted, moves to the graylist within days to weeks as the GFW detects suspicious patterns, and eventually gets blacklisted. This is why VPN users in Iran often need to rotate server IPs frequently.
     - Different ISPs (e.g., MCI Hamrah Aval vs. MTN Irancell) may maintain slightly different graylist/blacklist states, which is why a VPN server might work on one ISP but not another.
   - **6.4 Selective Bandwidth Throttling:** Distinct from outright blocking, the regime frequently throttles international bandwidth as a softer form of censorship.
     - Rather than fully blocking VPN traffic, the backbone may reduce bandwidth to make VPN connections painfully slow (e.g., reducing international throughput to near-unusable levels during protests or sensitive political events).
     - This throttling can be applied selectively -- targeting specific ISPs, specific protocols, specific destination IP ranges, or specific times of day.
     - This technique makes VPNs technically "work" but practically unusable for video calls, streaming, or even basic browsing, achieving the censorship goal without the political cost of a visible "blocked" page.

   - **6.5 Degradation-Based Filtering (DBF):** A newer and more sophisticated evolution of bandwidth throttling (section 6.4), DBF represents a fundamental paradigm shift in the GFW's approach: instead of binary blocking (connected vs. blocked), the firewall allows the connection to establish and even lets the TLS handshake begin, but then **systematically degrades the connection quality** to make it unusable.
     - **How DBF works:** Using DPI and behavioral fingerprinting (section 4.2), the GFW identifies encrypted sessions that don't match normal browser behavior. Instead of immediately dropping or resetting the connection, it manipulates network parameters through three dimensions of degradation:
       - **Network degradation:** Injecting artificial latency spikes, inducing probabilistic packet loss, and introducing jitter (variation in packet delivery timing).
       - **Resource degradation:** Artificially saturating CPU processing and creating interruptions in packet handling at intermediary nodes.
       - **Logical degradation:** Causing cascading timeouts at the application layer, making upper-layer protocols (HTTP/2 streams, gRPC calls, WebSocket keep-alives) fail in ways that appear as natural network instability.
     - **Why DBF is strategically important:** The primary goal is **plausible deniability**. Unlike explicit blocking (which produces a clear "blocked" signal that users and international observers can document), DBF makes the censorship look like ordinary infrastructure problems. The regime can attribute the degradation to "technical issues with operators" or "international backbone congestion," making it politically cheaper and harder to prove as intentional censorship.
     - **Protocol-specific vulnerabilities to DBF:**
       - **gRPC:** Due to its streaming nature and extreme sensitivity to latency, even small latency spikes cause the entire stream to reset.
       - **WebSocket:** The firewall manipulates keep-alive packets, trapping the client in an endless reconnection loop.
       - **HTTP/2:** Its strict dependency on packet ordering means that any packet loss locks the entire multiplexed channel (head-of-line blocking).
       - These protocol-specific weaknesses make DBF particularly effective against modern proxy transports that rely on these protocols for their tunneling layer.
     - **DBF vs. traditional blocking (comparison):**

       | Aspect | Traditional Filtering (Binary) | Degradation-Based Filtering (DBF) |
       | --- | --- | --- |
       | Connection state | Drop or RST immediately | Established but slow/unusable |
       | Detectability | High (clear block signal) | Very low (looks like bad network) |
       | Political cost | High (public outrage, documentation) | Low (plausible deniability) |
       | Primary tactic | IP/Domain/SNI blocking | Behavioral fingerprinting + degradation |
       | User experience | "Connection refused" | Endless loading, timeouts, buffering |

     - **Impact on circumvention tools:** Field testing in early 2026 shows that DBF renders most current tools ineffective not by blocking them, but by making them unbearably slow:
       - **V2Ray/Reality:** If the TLS fingerprint doesn't exactly match a real browser, the session is detected and degraded.
       - **TUN/TAP-based VPNs:** By converting all traffic into a single tunnel stream, they create a large and easy target for degradation.
       - **WireGuard:** Its fixed UDP patterns make it trivially identifiable for targeted degradation.
       - **Tor:** Not "blocked" in the traditional sense, but degraded to the point of being practically unusable.
       - **KCP and Paqet:** Some tools attempt to use the **KCP protocol** or the **Paqet** tool to mitigate the effects of artificial packet loss and jitter induced by DBF. These protocols are designed for high reliability over lossy links, which can help maintain a usable connection even when the GFW is actively inducing degradation.
     - **User fatigue as a goal:** A key strategic objective of DBF is to exhaust users psychologically. Rather than triggering outrage with a clear block, the constant frustration of slow, unreliable connections is designed to make users give up trying to access the free internet -- achieving the censorship goal through attrition rather than confrontation.

7. **Policy-Based and Architectural Control** (TIC backbone layer / `tic-tehran`, except 7.1 which runs on `tehran-ix`)
   - **7.1 Total National Internet Shutdown (The "Kill Switch"):** The regime can completely shut off international internet access by severing the connection at the TIC backbone level -- either by nullrouting international BGP routes or by dropping all international traffic at TIC's border routers.
     - This creates a total national blackout where even advanced VPNs and anti-filtering tools are useless, as there is no path from inside Iran to the global internet. This was most notably executed during the **January 2026 Protests**, where the regime implemented a complete severance of international links. Crucially, the domestic intranet (Iranian websites, banking, etc.) typically remains functional during these shutdowns because the IXP-to-ISP links stay up -- only TIC's international links are cut.
     - In the 2025 "stealth blackout," the regime even maintained global BGP route announcements (so it appeared from outside that Iran was still connected) while silently dropping all international traffic at the TIC backbone layer. This made the shutdown harder to detect and measure from abroad.
   - **7.2 Tiered Access and Whitelisting (The "National Information Network"):** The long-term goal is a model where the network defaults to blocking everything except a "whitelist" of approved domestic and international services.
     - This "National Intranet" often involves "Tiered Access," where different classes of users (e.g., journalists, students, government officials receiving "Cyber Freedom Areas") receive different levels of internet freedom and bandwidth, while the general populace is restricted to monitored domestic apps.
   - **7.3 Protocol Whitelisting (Default-Deny Posture):** During escalated censorship periods (such as the June 2025 stealth blackout), the backbone switches from a default-allow to a **default-deny** posture for protocol types.
     - In this mode, only a strict whitelist of protocols is permitted through the backbone -- typically only DNS, HTTP, and HTTPS. All other traffic (including UDP-based protocols, raw TCP on non-standard ports, ICMP beyond basic ping, etc.) is silently dropped.
     - This is a significant escalation beyond blocking specific protocols (section 6.2): instead of identifying and blocking bad traffic, the system blocks everything and only allows known-good traffic through. This renders most VPN and proxy tools useless because they rely on non-standard protocols or ports.
     - Even within the allowed protocols, the traffic is subject to all the other filtering layers (SNI inspection, DPI, behavioral analysis, etc.), so merely tunneling through HTTPS is not sufficient to evade detection.


## Simulation vs. Reality: Mocking Complex Services

In a real-world environment, many of the filtering mechanisms described above (such as dynamic IP reputation, active probing, and behavioral analysis) rely on complex, persistent backend services, high-performance DPI clusters, and real-time network monitoring.

To keep this test bed lightweight and focused on **enforcement logic** rather than developing a full-scale GFW, we simulate the results of these services using **Mock Configurations**. Instead of a real-time monitoring service identifying a "graylist" IP, we manually define these IPs in static configuration files.

The following mechanisms are currently implemented as mock-based simulations:

- **4.2 TLS Fingerprinting & 5.1 Encapsulated Protocol Detection:** Simulated via static hex-signature matching in `iptables`. In reality, this requires deep packet inspection (DPI) capable of stateful handshake analysis.
- **5.3 Active Probing:** Simulated by blocking a list of "confirmed" VPN IPs in `config/backbone/probed_ips.conf`. In reality, a government service would be actively scanning these IPs.
- **6.1 Behavioral Pattern Recognition:** Simulated using randomized packet drops and rate-limiting rules. In reality, this uses machine learning models and flow statistics.
- **6.3 Dynamic IP Reputation System:** Simulated by categorizing IPs into static Whitelist, Graylist, and Blacklist files. In reality, IPs move between these states dynamically based on global traffic patterns.
- **7.2 Tiered Access:** Simulated via a static whitelist of "privileged" IPs. In reality, this would be tied to a national identity and authentication system.

## 2026 Revolution of Iranians

also in 2026 Revolution of Iranians, the regime decided to completely block the internet, so they shut off the internet. they did it by shutting off the connection between the IXP and ISPs.

during these days, the Iran regime massacred the un-armed protesters, and killed at least 36'500 protesters in just 2 days. also they they started to execute the protesters in non official ways (without hanging them or public execution or ...), and they started to imprison the protesters in non official ways (without arresting them or public imprisonment or ...). so for a protester there is a high chance of being executed either in the streets or within a hospital, or during the arrest and transport or within the official or non official prisons, or for many cases in their own homes ...

because of the total shut down of the Internet, even the VPNs and anti-filtering tools were useless. some Iranians decided to connect to the Internet through Starlink devices. also some Iranians created some internal VPNs inside Iran intranet to reach these Starlink devices, which is a dangerous act, in case the regime find out about these internal VPNs, and trace the VPN creator or the Starlink device owner and the people who are using this starlink device or the internal VPN to the starlink devices.


now the regime has partially restored the internet, still way worse than before, but still some people can connect to the internet the normal VPNs and anti-filtering tools, alongeside the Starlink devices. so the previous VPN technologies like psiphon, v2ray, shadowsocks, etc. are still useful.

## purpose of this project

in this project, we are trying to create a test bed to simulate Iran network in an imperfect way, to test the VPNs and anti-filtering tools. this is not a perfect simulation, but it's a good enough simulation to test the VPNs and anti-filtering tools.


one can use this test bed to test and learn and practice a new anti-filtering tool, or one can use this as a setup for writing automated e2e test for developing these anti-filtering tools.



## tools

- containerlab
  - currently i decided to use containerlab to simulate the network, but i'm open to using other tools if you have a better tool in mind.

## simulation requirements

### node types

all nodes run as linux containers (`iran-sim:latest` image based on Ubuntu, unless noted otherwise). nodes marked `(R)` exist only in `topology-realistic.clab.yml`; nodes marked `(S)` exist only in `topology.clab.yml`; unmarked nodes appear in both.

#### border gateways `(R)`
- `gw-falcon` — FALCON submarine cable gateway. Connects `internet-srv` to `tic-south`. Represents the southern coast cable landing at Bandar Abbas. [TRANSIT PLANE]
- `gw-epeg` — EPEG terrestrial cable gateway. Connects `internet-srv` to `tic-west`. Represents the Turkey/Azerbaijan border cable entry at Tabriz. [TRANSIT PLANE]

#### TIC backbone mesh — AS49666 [TRANSIT PLANE]
- `tic-tehran` — TIC central hub. Main DPI/filtering chokepoint for all 20 filtering mechanisms. No direct international gateway; transit enters via `tic-south` and `tic-west`. Connected to `tehran-ix` for downstream distribution.
- `tic-south` `(R)` — TIC southern region (Bandar Abbas, Isfahan, Shiraz). Terminates FALCON cable via `gw-falcon`. Routes domestic traffic via `tic-tehran`.
- `tic-west` `(R)` — TIC western region (Tabriz, Urmia). Terminates EPEG cable via `gw-epeg`. Routes domestic traffic via `tic-tehran`.
- `tic-east` `(R)` — TIC eastern region (Mashhad). No direct international gateway; all traffic routes via `tic-tehran`.

#### internet exchange points [TRANSIT/PEERING handoff]
- `tehran-ix` — Tehran Internet Exchange. Bridges the transit plane (`tic-tehran`) and the peering plane (`tci`/`isp-shatel`/`aparat-server`). Also the kill-switch enforcement point (7.1).
- `isfahan-ix` `(R)` — Isfahan Internet Exchange. Regional peering point between `tic-south` and the south wholesale/ISP layer.
- `tabriz-ix` `(R)` — Tabriz Internet Exchange. Regional peering point between `tic-west` and the west wholesale/ISP layer.
- `mashhad-ix` `(R)` — Mashhad Internet Exchange. Regional peering point between `tic-east` and the east wholesale/ISP layer.

#### wholesale / transit aggregation — TCI AS58224 `(R)` [PEERING PLANE]
Note: TCI (Telecommunications Company of Iran, state-owned fixed-line incumbent) is distinct from TIC (backbone/transit). TCI is the wholesale aggregator between IXPs and retail ISPs.
- `tci` — TCI Tehran wholesale. Aggregates `isp-shatel`, `mob-mci`, and other Tehran-region ISPs. Connected to `tehran-ix`.
- `tci-south` — TCI South wholesale. Aggregates `isp-south` and `mob-irancell`. Connected to `isfahan-ix`.
- `tci-west` — TCI West wholesale. Aggregates `isp-west` and `mob-mci-west`. Connected to `tabriz-ix`.
- `tci-east` — TCI East wholesale. Aggregates `isp-east` and `mob-mci-east`. Connected to `mashhad-ix`.

#### fixed-line ISPs [PEERING PLANE]
- `isp-shatel` — Shatel (AS48434). Major retail fixed-line ISP in Tehran. Runs DNS filtering (dnsmasq) and ISP-layer nftables rules. Connects to `tci` (realistic) or directly to `tehran-ix` (simple).
- `isp-south` `(R)` — Mokhaberat South. Fixed-line ISP in Isfahan region. Connects to `tci-south`.
- `isp-west` `(R)` — Mokhaberat West. Fixed-line ISP in Tabriz region. Connects to `tci-west`.
- `isp-east` `(R)` — Mokhaberat East. Fixed-line ISP in Mashhad region. Connects to `tci-east`.

#### mobile carriers [MOBILE SUBSCRIBER PLANE]
- `client-android` `(S)` — Android-based end user (`redroid/redroid:14.0.0-latest` image). Connects to `isp-shatel` as a mobile subscriber. Conditionally enabled via `IRAN_MOBILE=true`.
- `mob-irancell` `(R)` — IranCell (AS44244). Second mobile operator (southern/provincial). Applies CGNAT (`scripts/cgnat.sh`): MASQUERADE on upstream interface, blocks unsolicited inbound. CEO replaced Jan 18, 2026 for resisting shutdown orders (FilterWatch). Connects subscribers (`client-mobile`) to `tci-south`.
- `mob-mci` `(R)` — MCI / Hamrah Aval Tehran (AS197207). Largest mobile operator. Connects to `tci`.
- `mob-mci-west` `(R)` — MCI mobile presence in Tabriz. Connects to `tci-west`.
- `mob-mci-east` `(R)` — MCI mobile presence in Mashhad. Connects to `tci-east`.

#### end users
- `iran-client` `(S)` — Standard Linux end user (fixed-line). Primary test client for the simple topology. Connects to `isp-shatel`.
- `client-tehran` `(R)` — Fixed-line end user in Tehran via `isp-shatel`.
- `client-south` `(R)` — Fixed-line end user in Isfahan via `isp-south`.
- `client-west` `(R)` — Fixed-line end user in Tabriz via `isp-west`.
- `client-east` `(R)` — Fixed-line end user in Mashhad via `isp-east`.
- `client-mobile` `(R)` — Mobile end user (Android subscriber) in the southern subscriber pool via `mob-irancell`.

#### NIN domestic content server [PEERING PLANE]
- `aparat-server` — NIN domestic content server (Aparat/Rubika equivalent). Connected **directly** to `tehran-ix` (eth3, 10.10.10.0/24). Has no path through `tic-tehran`. Remains reachable during international transit shutdowns (reflects Jan 2026 behavior: domestic banking/Eitaa/Rubika stayed up while all international transit was severed).

#### simulated internet
- `internet-srv` — Simulated global internet server (203.0.113.0/24, multiple IP aliases for testing blocklist, reputation, and probing scenarios). Connects to `gw-falcon` and `gw-epeg` (realistic) or directly to `tic-tehran` (simple).

#### academic / research `(R)`
- `ipm-academic` — IPM (AS6736). Iranian academic/research network gateway. Connected directly to `tic-tehran`. Represents a special-access path outside normal ISP routing.

#### UI utilities
- `scrcpy-web` `(S)` — Browser-based viewer for the Android client (`shmayro/scrcpy-web:latest` image). Accessible at `http://localhost:8000`. Conditionally enabled via `IRAN_MOBILE=true`.

## Usage

The simulation can be deployed in two modes from a single topology file: a standard mode with a Linux client, and a mobile mode that adds an Android client.

### 1. Standard Topology (Default)
This is the lightweight version using a standard Linux client. It works on most environments without special kernel requirements.

- **Deploy:** `clab deploy`
- **Destroy:** `clab destroy`

### 2. Mobile Topology (Optional)
This version adds a full Android environment (`redroid`) and a browser viewer (`scrcpy-web`), ideal for testing Android-specific VPN apps. To enable it, set the `IRAN_MOBILE` environment variable to `true`.

Note that this requires a host with **KVM support**.

- **Deploy:** `IRAN_MOBILE=true clab deploy`
- **Interact with Android:** Open `http://localhost:8000` in your browser after deployment.
- **Destroy:** `clab destroy`

### connectivity

**simple topology (`topology.clab.yml`):**
- international (transit): `iran-client → isp-shatel → tehran-ix → tic-tehran → internet-srv` [TRANSIT PLANE]
- domestic NIN (peering): `iran-client → isp-shatel → tehran-ix → aparat-server` [PEERING PLANE]

**realistic topology (`topology-realistic.clab.yml`):**
- international (transit, Tehran): `client-tehran → isp-shatel → tci → tehran-ix → tic-tehran → tic-south → gw-falcon → internet-srv` [TRANSIT PLANE]
- international (transit, south): `client-mobile → mob-irancell [CGNAT] → tci-south → isfahan-ix → tic-south → gw-falcon → internet-srv`
- domestic NIN (peering): `client-tehran → isp-shatel → tci → tehran-ix → aparat-server` [PEERING PLANE]
- cross-regional domestic: `client-south → isp-south → tci-south → isfahan-ix → tic-south → tic-tehran → tehran-ix → aparat-server` (east-west via tic-tehran hub)

**both topologies:**
- `tic-tehran` is connected to the real internet via its Docker bridge interface (`eth0`) with NAT/MASQUERADE, so clients can reach real-world services (google.com, x.com, etc.)
- `aparat-server` is reachable from within the Iranian network (via `tehran-ix`) but has no path through `tic-tehran`; it survives international shutdown scenarios
- DNS resolution typically uses the default Docker DNS (`127.0.0.11`). Note that in some environments like OrbStack, UDP port 53 can be unreliable, requiring a forced TCP configuration (`options use-vc` in `resolv.conf`), but this is not necessary in Docker Desktop for Mac.
- In OrbStack, the IPv4 is preferred over IPv6 via `gai.conf` (`precedence ::ffff:0:0/96 100`) since the topology only routes IPv4. (Note: This was required in OrbStack but is optional in Docker Desktop; currently disabled in topology).

### filtering simulation mplementation Status

| ID | Mechanism | Status | Implementation Method | Script |
| :--- | :--- | :--- | :--- | :--- |
| 1.1 | DNS Hijacking | ✅ Implemented | `nftables` NAT + `dnsmasq` | `1.1-dns-hijacking.sh` |
| 1.2 | DoH/DoT Blocking | ✅ Implemented | `nftables` IP/port drop + `iptables` DPI | `1.2-doh-dot-blocking.sh` |
| 2.1 | HTTP Host Filtering | ✅ Implemented | `iptables` string match | `2.1-http-host-filtering.sh` |
| 3.1 | IP Blocking | ✅ Implemented | `nftables` sets | `3.1-ip-blocking.sh` |
| 3.2 | BGP Hijacking | ✅ Implemented | `ip route` blackhole | `3.2-bgp-hijacking.sh` |
| 3.3 | IPv6 Filtering | ✅ Implemented | `nftables` ip6 drop | `3.3-ipv6-filtering.sh` |
| 4.1 | SNI Filtering | ✅ Implemented | `iptables` string match | `4.1-sni-filtering.sh` |
| 4.2 | TLS Fingerprinting | ✅ Implemented | `iptables` hex-string match | `4.2-tls-fingerprinting.sh` |
| 4.3 | TCP RST Injection | ✅ Implemented | `iptables` reject with tcp-reset | `4.3-tcp-rst-injection.sh` |
| 5.1 | Encapsulated Protocol | ✅ Implemented | `iptables` hex-string match | `5.1-encapsulated-protocol-detection.sh` |
| 5.2 | Packet Manipulation | ✅ Implemented | TCP stream reassembly proxy + `nft` IP frag drop | `5.2-packet-manipulation.sh` |
| 5.3 | Active Probing | ✅ Implemented | `nftables` mock IP block | `5.3-active-probing.sh` |
| 6.1 | Behavioral Pattern | ✅ Implemented | `nftables` random drop + rate limit | `6.1-behavioral-pattern-recognition.sh` |
| 6.2 | Protocol Throttling | ✅ Implemented | `nftables` UDP/443 drop | `6.2-protocol-specific-throttling.sh` |
| 6.3 | Dynamic IP Reputation| ✅ Implemented | `nftables` static reputation sets | `6.3-dynamic-ip-reputation.sh` |
| 6.4 | Bandwidth Throttling| ✅ Implemented | `tc qdisc` TBF | `6.4-selective-bandwidth-throttling.sh` |
| 6.5 | Degradation (DBF) | ✅ Implemented | `tc qdisc` Netem | `6.5-degradation-based-filtering.sh` |
| 7.1 | Kill Switch | ✅ Implemented | `nftables` forward drop | `7.1-kill-switch.sh` |
| 7.2 | Tiered Access | ✅ Implemented | `nftables` bypass sets | `7.2-tiered-access.sh` |
| 7.3 | Protocol Whitelist | ✅ Implemented | `nftables` default-deny | `7.3-protocol-whitelisting.sh` |

explanations:

- `1.1-dns-hijacking.sh` - DNS Hijacking and Poisoning

  This script simulates DNS hijacking at the ISP layer.

   * Mechanism: It uses nftables to redirect all DNS (UDP/TCP port 53) traffic originating from the
     iran-client (on interface eth1) to the isp-shatel's local DNS server (10.0.1.1:53).
   * Purpose: This forces clients to use the ISP's DNS, allowing the ISP to implement DNS-layer filtering
     (e.g., returning fake IPs for blocked domains).
   * Location: Runs on the `clab-iran-filtering-isp-shatel` container.
   * Commands used: nft add table, nft add chain, nft add rule for NAT redirection.
   * Usage:
       * on: Activates the DNS hijacking rules.
       * off: Deactivates (deletes) the DNS hijacking rules.
       * status: Checks if the dns_hijack nftables table exists, indicating if hijacking is active.

- `1.2-doh-dot-blocking.sh` - DoH and DoT Blocking

  This script simulates the blocking of DNS over HTTPS (DoH) and DNS over TLS (DoT) at the backbone layer.

   * Mechanism: It uses `nftables` to drop traffic to known public DoH/DoT provider IP addresses (e.g., Cloudflare, Google DNS) and also blocks TCP port 853, which is commonly used for DoT.
   * Purpose: To prevent users from bypassing ISP-level DNS poisoning by encrypting their DNS queries. By blocking access to secure DNS resolvers, the GFW forces clients to fall back to monitored DNS servers.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add set` (to define a set of IP addresses), `nft add element`, `nft add chain`, `nft add rule` for dropping packets based on destination IP or port.
   * Usage:
       * `on`: Activates the DoH/DoT blocking rules.
       * `off`: Deactivates (deletes) the DoH/DoT blocking rules.
       * `status`: Checks if the `doh_dot_blocking` `nftables` table exists, indicating if blocking is active.

- `2.1-http-host-filtering.sh` - HTTP Host Header Filtering

  This script simulates HTTP Host header inspection at the backbone layer.

   * Mechanism: It uses `iptables` string matching to inspect the `Host` header in plaintext HTTP (port 80) requests. If a blocked domain is found in the `config/backbone/http_blocklist.conf` file, the connection is dropped.
   * Purpose: Even if DNS filtering is bypassed, this mechanism can still block access to undesirable websites by examining the `Host` header in unencrypted HTTP traffic. This can lead to blockpages or connection resets in a real-world scenario.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `iptables -I FORWARD -p tcp --dport 80 -m string --string "Host: $domain" --algo bm -j DROP` to insert rules for string matching and dropping packets. `iptables -D` to delete rules.
   * Usage:
       * `on`: Reads domains from `http_blocklist.conf` and adds `iptables` rules to block them.
       * `off`: Deletes all `iptables` rules related to HTTP Host header filtering.
       * `status`: Checks if `iptables` rules for HTTP Host filtering on port 80 exist, indicating if filtering is active.

- `3.1-ip-blocking.sh` - Individual and Range (CIDR) Blocking

  This script simulates IP-based blocking at the backbone layer.

   * Mechanism: It uses `nftables` to create a set of IP addresses (`ip_blocklist`) from `config/backbone/blocklist.conf`. Any traffic destined to or originating from these IP addresses is then dropped.
   * Purpose: To block access to specific servers or entire CIDR ranges (e.g., cloud services used for VPNs or hosting blocked content), even if DNS filtering is bypassed and the client knows the direct IP. This is a critical layer of defense at the national chokepoint.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add set` (to define a set of IP addresses, with `flags interval` to support CIDR ranges), `nft add element` (to add IPs to the set), `nft add chain`, `nft add rule` for dropping packets based on source or destination IP address belonging to the `ip_blocklist` set.
   * Usage:
       * `on`: Reads IP addresses/CIDR ranges from `blocklist.conf`, creates an `nftables` set, and adds rules to drop traffic to/from these IPs.
       * `off`: Deletes the `nftables` table and associated rules for IP blocking.
       * `status`: Checks if the `ip_blocking` `nftables` table exists, indicating if IP blocking is active, and lists the blocked IPs.

- `3.2-bgp-hijacking.sh` - BGP Hijacking and Blackholing

  This script simulates BGP (Border Gateway Protocol) hijacking and blackholing at the backbone layer.

   * Mechanism: It simulates BGP hijacking by adding a "blackhole" static route for a specific victim IP prefix (`VICTIM_PREFIX`) on the `tic-tehran` container. This causes all traffic destined for that prefix to be dropped (blackholed) within the backbone, preventing it from reaching its intended destination.
   * Purpose: To simulate how a national-level actor can "kidnap" or "swallow" traffic for specific internet services by announcing more specific routes and then dropping that traffic, making the service unreachable. This is a powerful, low-level filtering technique that affects routing at a fundamental level.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `ip route add blackhole <IP/CIDR>` to add a blackhole route, and `ip route del blackhole <IP/CIDR>` to remove it. `ip route show` is used for status checking.
   * Usage:
       * `on`: Adds a blackhole route for the `VICTIM_PREFIX`.
       * `off`: Deletes the blackhole route.
       * `status`: Checks if a blackhole route for `VICTIM_PREFIX` exists, indicating if BGP hijacking simulation is active.

- `3.3-ipv6-filtering.sh` - IPv6 Systematic Filtering

  This script simulates the systematic filtering or disabling of IPv6 traffic at the backbone layer.

   * Mechanism: It uses `nftables` to drop all IPv6 traffic that passes through the `tic-tehran` container's forward chain. This effectively disables IPv6 connectivity for clients.
   * Purpose: To simulate how a regime might close potential "backdoors" that users could exploit to bypass IPv4-only filtering rules, especially as IPv6 adoption increases. By completely dropping IPv6 traffic, it ensures that filtering efforts are not circumvented.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table ip6` (to create an IPv6 specific table), `nft add chain ip6` (to create an IPv6 specific chain for forwarding), `nft add rule ip6 ... drop` to drop all IPv6 packets in the forward chain.
   * Usage:
       * `on`: Adds `nftables` rules to drop all IPv6 traffic.
       * `off`: Deletes the `nftables` table and associated rules for IPv6 filtering.
       * `status`: Checks if the `ipv6_filter` `nftables` table exists, indicating if IPv6 filtering is active.

- `4.1-sni-filtering.sh` - SNI (Server Name Indication) Filtering

  This script simulates SNI filtering at the backbone layer.

   * Mechanism: It uses `iptables` string matching to inspect the cleartext SNI field in TLS ClientHello packets (typically on TCP port 443). If a blocked domain (read from `config/backbone/sni_blocklist.conf`) is detected in the SNI, the connection is dropped.
   * Purpose: To block access to HTTPS websites even when DNS filtering has been bypassed. The SNI field, sent in plaintext during the initial TLS handshake, reveals the intended hostname, allowing the GFW to identify and block connections to blacklisted domains without decrypting the full traffic.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `iptables -I FORWARD -p tcp --dport 443 -m string --string "$domain" --algo bm -j DROP` to insert rules for string matching in the SNI field and dropping packets. `iptables -D` to delete rules.
   * Usage:
       * `on`: Reads domains from `sni_blocklist.conf` and adds `iptables` rules to block connections based on the SNI.
       * `off`: Deletes all `iptables` rules related to SNI filtering on port 443.
       * `status`: Checks if `iptables` rules for SNI filtering on port 443 exist, indicating if filtering is active.

- `4.2-tls-fingerprinting.sh` - TLS Fingerprinting and Session Behavioral Analysis

  This script simulates TLS fingerprinting (e.g., JA3/JA4) and session behavioral analysis at the backbone layer.

   * Mechanism: It uses `iptables` hex-string matching to detect known non-browser TLS handshake signatures in HTTPS traffic (port 443). Mock signatures are loaded from `config/backbone/tls_signatures.conf`. Uses a custom iptables chain (`TLS_FP_FILTER`) for organized rule management.
   * Purpose: To detect and block advanced circumvention tools that use encrypted tunnels, even if SNI is hidden or encrypted. The goal is to identify non-standard TLS clients and traffic patterns associated with VPNs, while allowing legitimate browser traffic.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `iptables -N` to create a custom chain, `iptables -A ... -m string --hex-string ... --algo bm -j DROP` for hex-based signature matching.
   * Usage:
       * `on`: Reads hex signatures from `tls_signatures.conf` and adds `iptables` rules to block matching TLS handshakes.
       * `off`: Removes the custom chain and all associated rules.
       * `status`: Checks if the `TLS_FP_FILTER` iptables chain exists, indicating if fingerprinting is active.

- `4.3-tcp-rst-injection.sh` - TCP RST Injection and Active Stream Interference

  This script simulates TCP RST (Reset) injection, a technique used to actively tear down TCP connections, at the backbone layer.

   * Mechanism: It uses `iptables` string matching (similar to 4.1) to inspect TLS ClientHello packets for blocked SNI domains from `config/backbone/sni_blocklist.conf`. Instead of silently dropping (like 4.1), it uses `REJECT --reject-with tcp-reset` to actively send RST packets. Uses a custom iptables chain (`SNI_RST_FILTER`) with both hex-based exact matching and subdomain dot-prefix matching.
   * Purpose: To simulate the GFW's active interference methods. When blocked content (like a forbidden SNI or HTTP Host header) is detected, the GFW doesn't just passively drop packets; it actively sends forged RST packets to both the client and server. This causes both ends of the connection to immediately close, making it appear as if the connection failed legitimately rather than being censored.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `iptables -N` to create a custom chain, `iptables -A ... -m string --hex-string ... --algo bm -j REJECT --reject-with tcp-reset` for SNI-based RST injection.
   * Usage:
       * `on`: Reads domains from `sni_blocklist.conf` and adds `iptables` rules to inject TCP RST for matching SNIs.
       * `off`: Removes the custom chain and all associated rules.
       * `status`: Checks if the `SNI_RST_FILTER` iptables chain exists, indicating if RST injection is active.

- `5.1-encapsulated-protocol-detection.sh` - Encapsulated Protocol Detection

  This script simulates Deep Packet Inspection (DPI) to detect and drop encapsulated protocols (like VMess/VLess/Shadowsocks) at the backbone layer.

   * Mechanism: It uses `iptables` hex-string matching to scan packet payloads for known proxy protocol signatures loaded from `config/backbone/encapsulated_signatures.conf`. Uses a custom iptables chain (`ENCAP_PROTO_FILTER`) for organized rule management. Each signature is matched using Boyer-Moore algorithm.
   * Purpose: To counter circumvention tools that hide their traffic within other protocols, making them harder to identify through simpler filtering methods like SNI or HTTP Host header inspection. This mechanism targets the payload itself for known VPN/proxy signatures.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `iptables -N` to create a custom chain, `iptables -A ... -m string --hex-string ... --algo bm -j DROP` for hex-based signature matching.
   * Usage:
       * `on`: Reads hex signatures from `encapsulated_signatures.conf` and adds `iptables` rules to drop matching packets.
       * `off`: Removes the custom chain and all associated rules.
       * `status`: Checks if the `ENCAP_PROTO_FILTER` iptables chain exists, indicating if detection is active.

- `5.2-packet-manipulation.sh` - Packet Manipulation and Fragmentation Interference

  This script simulates the GFW's countermeasures against TCP segmentation / TLS record fragmentation bypass techniques at the backbone layer.

   * Context: Anti-filtering tools (GoodbyeDPI, zapret, MahsaNG) split the TLS ClientHello across multiple small **TCP segments** so that the SNI field is spread across separate packets, evading per-packet DPI inspection.
   * Primary countermeasure (TCP stream reassembly): A transparent proxy (`scripts/sni-reassembly-proxy.py`) intercepts all port-443 traffic via `iptables REDIRECT`, reassembles the full TCP stream (just as a real DPI box would), extracts the SNI from the reconstructed ClientHello, and RSTs the connection if the SNI matches `config/backbone/sni_blocklist.conf`. Allowed traffic is forwarded transparently to the original destination. This defeats TCP segmentation and TLS record fragmentation because the proxy reads from the socket (which inherently reassembles TCP segments) before inspecting.
   * Secondary countermeasure (IP fragment drop): `nftables` rules drop all non-initial IP fragments (`ip frag-off & 0x3fff != 0 drop`), disrupting any tool or protocol relying on IP-level fragmentation.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `iptables -t nat ... -j REDIRECT --to-port 8443` for transparent proxy redirection. `python3 sni-reassembly-proxy.py` as the reassembly daemon. `nft add rule ... ip frag-off & 0x3fff != 0 drop` for IP fragment blocking.
   * Usage:
       * `on`: Starts the TCP stream reassembly proxy, sets up iptables REDIRECT, and enables IP fragment dropping rules.
       * `off`: Stops the proxy, removes iptables REDIRECT, and removes fragment dropping rules.
       * `status`: Reports whether the reassembly proxy is running and whether IP fragment blocking rules are active.

- `5.3-active-probing.sh` - Active Probing and Server Fingerprinting

  This script simulates the result of active probing by blocking IPs that have been "confirmed" as VPN/proxy servers at the backbone layer.

   * Mechanism: It uses `nftables` to create a set of IP addresses from `config/backbone/probed_ips.conf` (representing IPs confirmed via probing) and drops all traffic to/from these IPs. This simulates the outcome of active probing without implementing the actual probing logic.
   * Purpose: To proactively block VPN/proxy servers whose identity has been confirmed. In reality, government probing clients would actively scan suspected servers; here we mock that result with a static list of "confirmed" IPs.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add set` (with interval flags for CIDR support), `nft add element`, `nft add rule` for dropping traffic to/from probed IPs.
   * Usage:
       * `on`: Reads confirmed VPN IPs from `probed_ips.conf` and blocks them via `nftables`.
       * `off`: Deletes the `nftables` table and associated rules.
       * `status`: Checks if the `active_probing` nftables table exists, indicating if probing-based blocking is active.

- `6.1-behavioral-pattern-recognition.sh` - Behavioral Pattern Recognition and Statistics

  This script simulates behavioral pattern recognition and statistical filtering at the backbone layer.

   * Mechanism: It uses `nftables` to apply two heuristic rules: (1) random packet loss for large packets (simulating rejection of high-entropy encrypted flows), and (2) rate-limiting new connection bursts (simulating detection of protocol "churning" typical of VPN tools). Parameters are loaded from `config/backbone/behavioral_pattern.conf`.
   * Purpose: To detect and interfere with VPNs and other circumvention tools that might otherwise bypass simpler filtering methods. This is a simplified simulation of what would be ML-based behavioral analysis in reality.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add chain`, `nft add rule ... numgen random mod 100 < N drop` for probabilistic drops, `nft add rule ... ct state new limit rate over N/second ... drop` for burst rate limiting.
   * Usage:
       * `on`: Enables random packet loss and connection burst throttling based on config parameters.
       * `off`: Deletes the `nftables` table and all associated rules.
       * `status`: Checks if the `behavioral_pattern` nftables table exists, indicating if pattern recognition is active.

- `6.2-protocol-specific-throttling.sh` - Protocol-Specific Throttling (UDP/QUIC)

  This script simulates protocol-specific throttling, particularly for UDP-based protocols like QUIC, at the backbone layer.

   * Mechanism: It uses `nftables` to drop all UDP traffic on common QUIC/HTTP3 ports (loaded from `config/backbone/protocol_throttling.conf`, defaults to 443, 8443, 2053, 2083, 2087, 2096) in both directions (source and destination port).
   * Purpose: To force clients using modern, often encrypted, UDP-based protocols (like QUIC, WireGuard) to fall back to TCP. TCP traffic is generally easier for the GFW to inspect, manipulate, and filter (e.g., via SNI filtering or RST injection).
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add chain`, `nft add rule ... udp dport { ports } drop`, `nft add rule ... udp sport { ports } drop`.
   * Usage:
       * `on`: Adds `nftables` rules to drop all UDP traffic on configured QUIC ports.
       * `off`: Deletes the `nftables` table and associated rules for UDP/QUIC throttling.
       * `status`: Checks if the `protocol_throttling` `nftables` table exists, indicating if the throttling is active.

- `6.3-dynamic-ip-reputation.sh` - Dynamic IP Reputation System

  This script simulates a dynamic IP reputation system (Whitelist/Graylist/Blacklist) at the backbone layer using static configuration.

   * Mechanism: It uses `nftables` to create three sets of IP addresses from `config/backbone/ip_reputation.conf`: whitelisted IPs (accepted immediately), blacklisted IPs (dropped), and graylisted IPs (rate-limited and subject to 10% random packet loss). This simulates the outcome of a real-time reputation system using static categorization.
   * Purpose: To simulate tiered filtering based on IP reputation. In reality, IPs would dynamically move between categories based on traffic patterns; here we mock that with a static config file.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add set` (for each tier), `nft add element`, `nft add rule` with accept/drop/rate-limit actions per tier.
   * Usage:
       * `on`: Reads IP categorizations from `ip_reputation.conf` and creates `nftables` rules for each tier.
       * `off`: Deletes the `nftables` table and all associated rules.
       * `status`: Checks if the `ip_reputation` nftables table exists, indicating if the reputation system is active.

- `6.4-selective-bandwidth-throttling.sh` - Selective Bandwidth Throttling

  This script simulates selective bandwidth throttling for international traffic at the backbone layer.

   * Mechanism: It uses the `tc qdisc` (traffic control queueing discipline) command to add a Token Bucket Filter (TBF) to the network interface (`eth1`) connecting to the internal Iranian network. This limits the egress bandwidth from the backbone to a specified rate loaded from `config/backbone/bandwidth_throttling.conf` (defaults to 256kbit).
   * Purpose: To make international connections painfully slow, even if they are not outright blocked. This is a "softer" form of censorship that aims to make services practically unusable for activities like video calls or streaming, achieving the censorship goal through attrition.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `tc qdisc add dev <interface> root tbf rate <rate> latency <latency> burst <burst>` to add a TBF qdisc. `tc qdisc del` to remove it.
   * **Note:** This script is mutually exclusive with 6.5 (DBF) -- both use the root qdisc on the same interface. Enabling one replaces the other.
   * Usage:
       * `on`: Applies bandwidth throttling to the specified interface.
       * `off`: Removes bandwidth throttling from the interface.
       * `status`: Checks if a TBF qdisc is active on the interface, indicating if throttling is enabled, and reports the configured rate.

- `6.5-degradation-based-filtering.sh` - Degradation-Based Filtering (DBF)

  This script simulates Degradation-Based Filtering (DBF) at the backbone layer, systematically degrading connection quality.

   * Mechanism: It uses the `tc qdisc` command with the `netem` (network emulator) discipline to inject artificial latency, jitter, and packet loss on the network interface (`eth1`) connecting to the internal Iranian network. Parameters are loaded from `config/backbone/degradation.conf`.
   * Purpose: To simulate a sophisticated form of censorship that doesn't outright block connections but makes them unusable by degrading quality. This aims for "plausible deniability" by making censorship appear as ordinary network instability, frustrating users without providing clear evidence of blocking.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `tc qdisc add dev <interface> root netem delay <delay> <jitter> loss <loss>` to add netem rules. `tc qdisc del` to remove it.
   * **Note:** This script is mutually exclusive with 6.4 (Bandwidth Throttling) -- both use the root qdisc on the same interface. Enabling one replaces the other.
   * Usage:
       * `on`: Applies network degradation (delay, jitter, packet loss) to the specified interface.
       * `off`: Removes network degradation from the interface.
       * `status`: Checks if a `netem` qdisc is active on the interface, indicating if DBF is enabled, and reports the configured parameters.

- `7.1-kill-switch.sh` - Total National Internet Shutdown (The "Kill Switch")

  This script simulates a total national internet shutdown (the "kill switch") at the IXP layer.

   * Mechanism: It uses `nftables` to drop all traffic (both incoming and outgoing) on the interface (`eth1`) connecting the `tehran-ix` to the `isp-shatel`. This severs the connection between the IXP and ISPs.
   * Purpose: To simulate a complete national internet blackout, making advanced VPNs and anti-filtering tools useless as there is no path from inside Iran to the global internet. This mechanism can also be used to selectively cut off parts of the network.
   * **Note:** The kill switch operates at the IXP layer (not the backbone) and overrides ALL access, including Tiered Access (7.2) privileged users. This is by design -- a total shutdown affects everyone.
   * Location: Runs on the `clab-iran-filtering-tehran-ix` container.
   * Commands used: `nft add table inet`, `nft add chain inet`, `nft add rule ... iifname <interface> drop`, `nft add rule ... oifname <interface> drop`.
   * Usage:
       * `on`: Activates the kill switch, dropping all traffic on the specified interface.
       * `off`: Deactivates the kill switch, restoring internet connectivity.
       * `status`: Checks if the `kill_switch` `nftables` table exists, indicating if the kill switch is active.

- `7.2-tiered-access.sh` - Tiered Access and Whitelisting

  This script simulates a tiered access and whitelisting system at the backbone layer.

   * Mechanism: It uses `nftables` to define a set of "privileged" IP addresses (`privileged_ips`) from `config/backbone/privileged_ips.conf` and creates a high-priority (`priority -200`) forward chain that marks packets from/to these IPs with `meta mark 0x10`. **All filtering scripts** check for this mark and accept the packet early -- both nftables chains (via `meta mark 0x10 accept`) and iptables custom chains (via `-m mark --mark 0x10 -j ACCEPT`). This two-step approach (mark + check) is necessary because in nftables, an `accept` verdict in one base chain does not prevent evaluation by other base chains at the same hook. The shared mark value and helper functions are defined in `scripts/common.sh`. When 7.2 is enabled after other filters, it injects exemptions into all currently active filtering chains. When filters are enabled after 7.2, they insert their own exemptions via `common.sh` helpers. The only exception is 7.1 (Kill Switch), which overrides everything including privileged access.
   * Purpose: To simulate a model where certain users or entities (e.g., government officials, specific organizations) receive different levels of internet freedom by being whitelisted from general filtering rules, while the general populace remains restricted.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table ip`, `nft add set ip`, `nft add element ip`, `nft add chain ... priority -200` for high-priority marking, `nft add rule ... meta mark set 0x10` for privileged IPs. Injects exemption rules into all active nftables tables and iptables custom chains.
   * Usage:
       * `on`: Reads privileged IPs from `privileged_ips.conf`, creates an `nftables` set, marks privileged traffic, and injects exemption rules into all active filtering chains (both nftables and iptables).
       * `off`: Removes exemption rules from all filtering chains and deletes the `nftables` table, set, and marking chain.
       * `status`: Checks if the `global_whitelist` table and `privileged_ips` set exist, indicating if tiered access is active.

- `7.3-protocol-whitelisting.sh` - Protocol Whitelisting (Default-Deny Posture)

  This script simulates protocol whitelisting with a default-deny posture at the backbone layer.

   * Mechanism: It uses `nftables` to create a `forward` chain with a default policy of `drop`, meaning all traffic is blocked by default. Then, specific rules are added to explicitly `accept` traffic for whitelisted protocols: DNS (UDP/TCP 53), HTTP (TCP 80), HTTPS (TCP 443), and ICMP (ping). If Tiered Access (7.2) is active, packets marked with the privileged mark (`0x10`) are also accepted, ensuring government officials and other privileged users bypass the default-deny posture.
   * Purpose: To simulate an escalated censorship period where the network switches from allowing everything unless explicitly blocked, to blocking everything unless explicitly allowed. This significantly restricts the types of traffic permitted, rendering most non-standard VPN and proxy protocols unusable.
   * Location: Runs on the `clab-iran-filtering-tic-tehran` container.
   * Commands used: `nft add table`, `nft add chain ... policy drop`, `nft add rule ... accept`, `nft add rule ... meta mark 0x10 accept` (if 7.2 is active).
   * Usage:
       * `on`: Activates the default-deny policy, whitelists specific protocols, and integrates with tiered access if active.
       * `off`: Deactivates protocol whitelisting by deleting the `nftables` table.
       * `status`: Checks if the `protocol_whitelisting` `nftables` table exists, indicating if whitelisting is active.

### image and tooling
- the base image is Ubuntu (`Dockerfile.sim`) with: iproute2, iptables, nftables, curl, iputils-ping, dnsutils, net-tools, dnsmasq
- bash is available in all containers
- additional packages should be added to `Dockerfile.sim` as needed
- `scripts/common.sh` defines shared constants (e.g., the privileged mark `0x10`) and helper functions used by all filtering scripts for Tiered Access (7.2) integration

### Testing and Verification

To ensure the simulation accurately represents the intended network topology and filtering behaviors, an automated test suite is provided in `test.sh`. This script is crucial for verifying that changes to configurations (like `nftables` rules or `dnsmasq` settings) or the topology itself do not break the expected flow or filtering logic.

#### test.sh Overview
The `test.sh` script performs a comprehensive series of automated checks across the entire infrastructure, covering all 20 filtering mechanisms. Each filtering test follows the pattern: verify initially OFF, enable, test blocking behavior, disable, verify restored.

**Infrastructure checks (sections 1-4):**
1.  **Container Health:** Verifies all 6 nodes are running.
2.  **Network Connectivity (Layer 3):** Pings through the full chain (client -> ISP -> IXP -> backbone -> internet).
3.  **DNS Resolution (Unblocked):** Confirms non-censored domains resolve and are reachable.
4.  **Service & System Verification:** Checks dnsmasq and IP forwarding on intermediary nodes.

**Filtering mechanism tests (sections 5-25):**
5.  **DNS Hijacking (1.1):** Validates blocked domains resolve to censorship IP (`10.10.34.34`).
6.  **DoH/DoT Blocking (1.2):** Verifies known DNS providers (1.1.1.1, 8.8.8.8) become unreachable.
7.  **HTTP Host Filtering (2.1):** Tests that HTTP requests with blocked Host headers are dropped while allowed hosts pass.
8.  **IP Blocking (3.1):** Tests blocked IPs become unreachable.
9.  **BGP Hijacking (3.2):** Tests blackholed prefixes become unreachable.
10. **IPv6 Filtering (3.3):** Verifies ip6 drop rules are created.
11. **SNI Filtering (4.1):** Tests that TLS connections with blocked SNI are dropped while allowed SNIs pass.
12. **TLS Fingerprinting (4.2):** Verifies hex-pattern matching rules are created in iptables.
13. **TCP RST Injection (4.3):** Tests that connections to blocked SNIs receive TCP RST.
14. **Encapsulated Protocol Detection (5.1):** Verifies hex-pattern matching rules are created.
15. **Packet Manipulation (5.2):** Tests TCP stream reassembly (proxy blocks segmented blocked SNI, forwards segmented allowed SNI) and IP fragment drop rules.
16. **Active Probing (5.3):** Tests probed VPN IPs become unreachable.
17. **Behavioral Pattern Recognition (6.1):** Verifies random drop and rate limit rules exist.
18. **Protocol Throttling (6.2):** Verifies UDP port drop rules exist.
19. **Dynamic IP Reputation (6.3):** Tests blacklisted IPs are blocked, whitelisted IPs pass.
20. **Bandwidth Throttling (6.4):** Verifies TBF qdisc is applied.
21. **Degradation-Based Filtering (6.5):** Verifies netem qdisc is applied.
22. **Kill Switch (7.1):** Tests total shutdown: internet, internet-srv, and intranet all become unreachable.
23. **Tiered Access (7.2):** Verifies privileged IP set and mark exemption injection into active filters.
24. **Protocol Whitelisting (7.3):** Tests default-deny: whitelisted ports work, non-whitelisted ports blocked.
25. **7.2 + 7.3 Integration:** Tests mark-based exemption works regardless of enable order.

#### Usage
It is recommended to run the tests after every deployment or configuration change:
```bash
# Rebuild and redeploy
clab destroy && ./build.sh && clab deploy

# Run the test suite
./test.sh
```

## References

The information about Iran's filtering techniques described above is informed by the following sources:

- **IRBlock: A Large-Scale Measurement Study of the Great Firewall of Iran** (USENIX Security 2025) -- University of British Columbia & University of Waterloo. Comprehensive measurement of DNS poisoning, HTTP blockpage injection, and UDP disruption affecting millions of IPs. https://www.usenix.org/system/files/usenixsecurity25-tai.pdf
- **Degradation-Based Filtering (DBF) analysis** -- filtershekan.sbs technical report on the new paradigm shift from binary blocking to smart quality degradation, including field testing results of TLS vs. non-TLS transports across multiple ISPs (Bahman 1404 / early 2026). https://filtershekan.sbs/DBF/
- **Tightening the Net: China's Infrastructure of Oppression in Iran** -- ARTICLE 19 report on Chinese companies (Huawei, ZTE, Hikvision, Tiandy) supplying surveillance and filtering technology to Iran. https://www.article19.org/resources/tightening-the-net-chinas-infrastructure-of-oppression-in-iran/
- **Iran's Stealth Internet Blackout: A New Model of Censorship** -- Arash Aryapour (arXiv 2025). Analysis of the June 2025 "stealth blackout" including protocol whitelisting, DPI, and throttling techniques. https://arxiv.org/html/2507.14183v1
- **Iran's 'Stealth Blackout': A Multi-stakeholder Analysis of the June 2025 Internet Shutdown** -- Filterwatch / Miaan Group. Multi-phase shutdown analysis including SNI blocking and DPI evolution. https://filter.watch/english/2025/10/02/irans-stealth-blackout-a-multi-stakeholder-analysis-of-the-june-2025-internet-shutdown/
- **Evolving Digital Censorship in Iran: A Deep Dive into Network Restrictions and Circumvention** -- breakingnasdaq.beehiiv.com. Detailed report on protocol blocking, IP reputation system (whitelist/graylist/blacklist), active probing, and DPI upgrades. https://breakingnasdaq.beehiiv.com/p/evolving-digital-censorship-in-iran
- **I(ra)nconsistencies: Novel Insights into Iran's Censorship** -- Felix Lange et al., Paderborn University (2025). DNS and HTTP censorship analysis. https://censorbib.nymity.ch/pdf/Lange2025a.pdf
- **Russia Allegedly Helped Iran Shut Down Internet Nationwide Using Advanced Tech** -- United24 Media. Report on Russian DPI technology (Protei), electronic warfare systems, and multi-layered censorship architecture. https://united24media.com/latest-news/russia-allegedly-helped-iran-shut-down-internet-nationwide-using-advanced-tech-15044
- **Detecting and Evading Censorship-in-Depth: A Case Study of Iran's Protocol Filter** -- University of Maryland (FOCI 2020). Reverse-engineering of Iran's protocol filter and evasion techniques. https://www.cs.umd.edu/~dml/papers/iran_foci20.pdf
- **A Comparative Look at Internet Shutdowns in Iran: 2019, 2022, 2025, 2026** -- Human Rights Activists (HRA). Historical comparison of shutdown methods and evolution. https://www.hra-iran.org/a-comparative-look-at-internet-shutdowns-in-iran-2019-2022-2025-2026/
- **The Guardian: Chinese technology underpins Iran's internet control** (February 2026). https://www.theguardian.com/world/2026/feb/09/china-iran-technology-internet-control
- **KCP: A Fast and Reliable ARQ Protocol.** https://github.com/skywind3000/kcp
- **Paqet: A tool for network analysis and circumvention.** https://github.com/hanselime/paqet
