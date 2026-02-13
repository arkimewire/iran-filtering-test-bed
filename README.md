# Iran Internet Filtering Simulation

This project provides a container-based test bed to simulate Iran's complex internet filtering and censorship infrastructure. It is designed for developers, researchers, and activists to test, develop, and understand anti-filtering tools and techniques in a controlled environment.

The simulation is built using [Containerlab](https://containerlab.dev/) and models the multi-layered network topology of Iran, including the Backbone/GFW, IXP, and ISP layers.

For a deep dive into the project's philosophy, the real-world censorship techniques being simulated, and the detailed architecture, please see **[AGENTS.md](AGENTS.md)**.

## Devcontainer Environment

This project is configured to run inside a **[Dev Container](https://containers.dev/)**. This makes setup seamless, as all required tools, including `containerlab`, are automatically installed inside the containerized environment.

The only prerequisite you need on your host machine is **[Docker](https://docs.docker.com/get-docker/)**.

## Quick Start

### 1. Open in Devcontainer
Open this project in your code editor (e.g., VS Code with the Dev Containers extension) and use the "Reopen in Container" command.

### 2. Build the Simulation Image
Once inside the devcontainer, open a terminal and build the custom `iran-sim` container image used by the lab nodes:
```bash
./build.sh
```

### 3. Deploy the Simulation
The simulation can be deployed in two modes:

#### Standard Topology
This is the lightweight version using a standard Linux client. It can run on any host OS that supports Docker (Linux, macOS on Apple Silicon, Windows).

- **Deploy:**
  ```bash
  clab deploy
  ```
- **Destroy:**
  ```bash
  clab destroy
  ```

#### Mobile Topology (Linux Host Required)
This version adds a full Android environment for testing mobile-specific apps. Due to the requirements of the Android emulator (`redroid`), this mode **must be run on a Linux host**. See the Host Environment Requirements section below for details.

- **Deploy:**
  ```bash
  IRAN_MOBILE=true clab deploy
  ```
- **Interact with Android:** After deployment, open `http://localhost:8000` in your browser.
- **Destroy:**
  ```bash
  clab destroy
  ```

---

## Host Environment Requirements

### Standard Topology
The standard topology is platform-independent and will work on any system where you can run Docker, including Linux, Windows (with WSL2), and macOS (including Apple Silicon).

### Mobile Topology (Linux Only)
The mobile simulation requires features (KVM and the `binder` driver) that are only available when the devcontainer is run on a Linux host.

Before running the mobile topology, ensure the following kernel modules are loaded on your **Linux host machine**:
```
nft_nat
nft_masq
nft_chain_nat
nft_ct
nft_numgen
nf_conntrack
nf_nat
nf_nat_redirect
xt_string
xt_REDIRECT
sch_tbf
sch_netem
nft_compat
ip_tables
iptable_filter
nfnetlink_queue
nft_queue
nft_redir
binder_linux
xt_comment
```
You can typically ensure they are loaded on boot by creating a file in `/etc/modules-load.d/`. For example:
```bash
# On your Linux host machine, create this file:
# /etc/modules-load.d/iran-filtering-lab.conf
#
# And add the module names listed above. Then restart the service:
# sudo systemctl restart systemd-modules-load.service
```
