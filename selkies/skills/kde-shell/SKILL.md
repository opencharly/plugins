---
name: kde-shell
description: >
  The SDDM-free KDE Plasma Wayland SESSION package leaf — the package set shared
  by the bare-metal KDE desktop (kde-desktop) and the headless streamed KDE pod
  (kde-selkies). MUST be invoked before editing the kde-shell or kde-desktop
  package partition.
---

# kde-shell — SDDM-free Plasma session package leaf

`kde-shell` is a package-only candy holding the KDE Plasma Wayland SESSION that
is common to BOTH KDE consumers, so the package list is defined once (R3):

- **`kde-desktop`** (bare-metal seat) = `kde-shell` + `sddm` + workstation-only
  extras + `systemctl set-default graphical.target`.
- **`kde-selkies`** (headless streamed pod) = `require: [selkies, kde-shell, …]`
  — Plasma without a display manager.

## Partition (what's in kde-shell vs kde-desktop)

`kde-shell` (arch): `plasma-desktop` (the deps-puller for plasma-workspace +
**kwin_wayland + plasmashell** + kf6 + qt6 + breeze) + `xorg-xwayland` + the core
session components (plasma-pa, plasma-nm, powerdevil, kscreen, kde-gtk-config,
breeze-gtk, kdialog, kio-admin) + curated apps usable in both venues (ark,
dolphin, konsole, kate, kcalc, gwenview, spectacle) + `kdotool` (AUR) — the
KWin window-management automation the `wl:` verb drives on KWin (the KWin analogue
of wlroots' `wlrctl toplevel`; KWin-only, so it lives here not in `wl-tools`).
`require: [dbus]`.

`kde-desktop` KEEPS the **workstation-only** extras that would only bloat the
headless streaming pod: sddm, plasma-systemmonitor, plasma-browser-integration,
plasma-firewall/thunderbolt, kdeplasma-addons, kwallet-pam/kwalletmanager,
bluedevil, kinfocenter, partitionmanager, kdeconnect, media players.

## Related

- `/charly-selkies:kde-selkies` — headless streamed Plasma consumer (pod).
- `/charly-check:wl` — uses this candy's `kdotool` for KWin window management.
- `/charly-distros:cachyos` — the CachyOS/Arch base (Plasma packages are pac/AUR).
- `/charly-image:layer` — package-section authoring (`distro.arch.package`).
