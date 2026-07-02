---
name: debug-tools-layer
description: |
  Debug toolkit for inspecting deployed services from inside the container — network probes (ip/ss/lsof/ping/dig/nc/socat/tcpdump/traceroute/mtr/wget), process inspection (ps/top/htop/pgrep/free/vmstat/strace/ltrace), file inspection (file/tree/xxd/vim/nano), system stats (iotop/iftop/sysstat), session helpers (tmux/rsync/yq). Distro-agnostic.
  Use when working with the debug-tools layer, the per-distro package-name divergence (nmap-ncat vs ncat vs gnu-netcat), or the 16 build-scope check probes that lock in headline binary presence.
---

# debug-tools — distro-agnostic debug toolkit

Single-purpose layer that installs ~50 standard debugging utilities
across 5 categories: network, process, file, system stats, session
helpers. Composed by `/charly-versa:versa` so operators can debug
the deployed services (marimo, airflow, martin, maputnik, etc.) from
INSIDE the running container.

Without this layer, `charly cmd versa "ps"` returns
"command not found" — minimal Fedora images don't ship procps-ng,
iproute, bind-utils, etc. by default.

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | none |
| Distros | fedora, arch, debian, ubuntu (per-distro package lists) |
| Ports | none |
| Services | none |
| Volumes | none |
| Check probes | 16 build-scope (one per headline binary) |

## Tool catalog

### Network

`ip`, `ss`, `netstat`, `lsof`, `ping`, `dig`, `nslookup`, `nc`,
`socat`, `tcpdump`, `traceroute`, `mtr`, `wget`

Cover the full DNS / TCP / packet-capture / ICMP / port-relay surface.
`curl` already comes from elsewhere (jq layer dep), so `wget`
complements it.

### Process

`ps`, `top`, `htop`, `pgrep`, `pkill`, `kill`, `killall`, `pidof`,
`free`, `vmstat`, `watch`, `slabtop`, `strace`, `ltrace`, `iotop`,
`iftop`

Process inspection (procps-ng) + system tracing (strace/ltrace) +
I/O & network tops (iotop/iftop).

### File / text

`file`, `tree`, `vim`, `nano`, `xxd`

`xxd` ships with `vim-common` (auto-installed alongside vim-enhanced).

### System stats

`sysstat` package provides `iostat`, `mpstat`, `pidstat`, `sar`,
`sadf` — historical metrics + per-task accounting.

### Session helpers

`tmux`, `rsync`, `yq`

Multi-pane shell sessions, file sync, YAML manipulation.

## Per-distro package divergence

Tool names aren't portable — each distro is enumerated separately
to avoid silent "installed nothing" on the wrong distro:

| Tool | fedora | arch | debian | ubuntu |
|---|---|---|---|---|
| Process basics (ps, top, free, kill, pgrep, vmstat) | `procps-ng` | `procps-ng` | `procps` | `procps` |
| ip + ss + tc | `iproute` | `iproute2` | `iproute2` | `iproute2` |
| netstat + ifconfig | `net-tools` | `net-tools` | `net-tools` | `net-tools` |
| dig + nslookup + host | `bind-utils` | `bind-tools` | `dnsutils` | `dnsutils` |
| ping | `iputils` | `iputils` | `iputils-ping` | `iputils-ping` |
| nc | `nmap-ncat` | `gnu-netcat` | `ncat` | `ncat` |
| traceroute | `traceroute` | `traceroute` | `traceroute` | `traceroute` |
| mtr | `mtr` | `mtr` | `mtr-tiny` | `mtr-tiny` |
| vim | `vim-enhanced` | `vim` | `vim` | `vim` |
| yq | `yq` (Fedora py) | `go-yq` (mikefarah Go) | (omitted — snap-only) | (omitted) |

Single common name (`socat`, `tcpdump`, `lsof`, `file`, `tree`,
`nano`, `htop`, `strace`, `ltrace`, `iotop`, `iftop`, `sysstat`,
`tmux`, `rsync`, `wget`) covers all four distros.

## Check coverage (16 probes — locks in headline binaries)

Spot-checks one binary per category. If a future package rename
breaks one, the build fails loudly at image build time:

- `ps-binary`, `ss-binary`, `lsof-binary`, `ping-binary`, `dig-binary`,
  `nc-binary`, `tcpdump-binary` — network/process headlines
- `htop-binary`, `strace-binary` — interactive/tracing
- `vim-binary`, `nano-binary`, `tree-binary`, `file-binary` — file/text
- `tmux-binary`, `wget-binary`, `rsync-binary` — session/transfer

`ping-binary` and `nc-binary` are checked via `command -v` rather
than file path because the binary's location varies across distros
(Fedora: `/usr/bin/ping`; Debian: `/usr/bin/ping` but historically
`/bin/ping`).

## Use case: debugging versa services

| Scenario | Tools |
|---|---|
| "Is martin actually listening on 3000?" | `ss -tlnp \| grep 3000`, `lsof -i :3000` |
| "What's the airflow scheduler doing?" | `ps auxf \| grep airflow`, `htop`, `strace -p <pid>` |
| "Is the marimo MCP responding?" | `curl http://localhost:2718/mcp/server`, `nc -zv localhost 2718` |
| "Why is the GTFS download slow?" | `iftop -i eth0`, `traceroute api.transitous.org` |
| "Is the workspace volume filling up?" | `du -sh /workspace/*`, `iotop` |
| "What's eating CPU?" | `htop`, `pidstat -u 1` |

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:airflow-layer` — services this toolkit debugs
- `/charly-versa:osm-tools-layer` — martin server this toolkit debugs
- `/charly-versa:versa-layer` — marimo runtime this toolkit debugs
- `/charly-coder:dev-tools` — overlapping but heavier (includes qemu, AWS CLI, etc.); not composed by versa
