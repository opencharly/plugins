---
name: asciinema
description: |
  Terminal session recorder (asciinema).
  Use when working with the asciinema candy.
---

# asciinema -- Terminal session recorder

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

RPM: `asciinema`

## What It Does

Records terminal sessions as `.cast` files (asciicast v2 format). Recordings capture timing, input, and output — can be replayed with `asciinema play`, uploaded to asciinema.org, or converted to GIF/video.

## Cross-distro coverage

RPM: `asciinema` · PAC: `asciinema` · DEB: `asciinema` — full parity.

## Usage

```yaml
# box or candy charly.yml — composition is a child node, not a top-level list
my-box:
    candy:
        base: fedora
    my-box-candy:
        candy:
            - asciinema
```

Used by the `record:` check verb (a `record: start` step with `record_mode: terminal`) for terminal recording sessions. Also available standalone via `asciinema rec`.

## Integration with the `record:` check verb

Author ordered `record:` plan steps (the declarative verb served out-of-process by
`candy/plugin-record` — there is no host `charly check` subcommand for it) and run them
with `charly check live <image> --filter record`:

```yaml
term-start:
    check: a terminal recording starts
    record: start
    context: [deploy]
    record_name: demo
    record_mode: terminal
term-echo:
    check: a command is sent into the recording
    record: cmd
    context: [deploy]
    record_name: demo
    text: echo hello
term-stop:
    check: the recording stops and is copied out
    record: stop
    context: [deploy]
    record_name: demo
    artifact: demo.cast
```

```bash
charly check live <image> --filter record   # runs the steps above
asciinema play demo.cast                     # play back the copied-out artifact
```

## Note

Also available via the `dev-tools` candy (which includes asciinema among many other tools). This standalone candy is for boxes that need terminal recording without the full dev-tools bundle.

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Commands

- `/charly-check:record` — Terminal recording via asciinema (start, stop, cmd)

## Cross-References

- `/charly-check:record` — the `record:` check verb (`record_mode: terminal`) uses asciinema
- `/charly-coder:dev-tools` — Also includes asciinema (larger candy)

## When to Use This Skill

Use when the user asks about:
- Terminal session recording
- asciinema in containers
- The `asciinema` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
