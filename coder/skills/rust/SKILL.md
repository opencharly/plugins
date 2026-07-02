---
name: rust
description: |
  Rust compiler and Cargo package manager via system packages (RPM/DEB).
  Use when working with Rust development or Cargo builds.
---

# rust -- Rust compiler and Cargo

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |

PATH additions: `~/.cargo/bin`

## Packages

RPM: `rust`, `cargo`
DEB: `rustc`, `cargo`

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - rust
```

## Used In Boxes

- No enabled boxes use this candy directly
- Transitive dependency of `language-runtimes`

## When to use the `rust` candy vs the `build-toolchain` `rust`+`cargo` packages

Two places now ship a Rust toolchain. Choose based on **where** you need it:

| Need | Use |
|------|-----|
| Rustc/cargo at **runtime** in the final container (developer shells, CI runners, on-the-fly cargo builds) | Add `/charly-coder:rust` to the runtime candies list of the box |
| Rustc/cargo at **build time only**, for compiling a cdylib that's copied into the final image (e.g., pixelflux_wayland) | Already provided by `/charly-distros:fedora-builder` via `/charly-coder:build-toolchain`'s system `rust`+`cargo` packages — no extra candy needed |

Builder-stage cargo (the build-toolchain path) keeps the runtime image small because the
toolchain stays in the multi-stage builder and never lands in the final layers.

## Related Candies

- `/charly-coder:language-runtimes` -- includes rust as a dependency
- `/charly-coder:build-toolchain` -- now also ships `rust`+`cargo` for builder-stage compilation

## When to Use This Skill

Use when the user asks about:

- Rust compiler in containers
- Cargo builds or Rust development
- The `rust` candy

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, env_provide, tests block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block
