---
name: comfyui-layer
description: |
  ComfyUI image generation service on port 8188 with CUDA GPU support.
  Use when working with ComfyUI, image generation, Stable Diffusion, or AI art pipelines.
---

# comfyui -- GPU-accelerated image generation service

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `cuda`, `supervisord` |
| Ports | 8188 |
| Volumes | `comfyui` -> `~/ComfyUI` |
| Service | `comfyui` (supervisord) |
| Install files | `plan:`, `pixi.toml` |

## Packages

The candy is multi-distro:

- `aria2` (RPM / PAC) -- download manager for model files
- `git-lfs` (RPM / PAC) -- large file support for model repos

On Arch/CachyOS the `distro.arch` section installs `aria2` and `git-lfs` from the
Arch repos (same package names).

## Environment Variables

| Variable | Value |
|----------|-------|
| (inherited from cuda) | CUDA toolkit paths |

## Usage

```yaml
# charly.yml — the comfyui box composes the comfyui candy via an inline candy: list
comfyui:
  candy:
    base: nvidia
    candy:
      - comfyui
```

## Used In Boxes

- `/charly-comfyui:comfyui`

## Related Candies

- `/charly-distros:cuda` -- CUDA toolkit dependency
- `/charly-infrastructure:supervisord` -- process manager dependency

## When to Use This Skill

Use when the user asks about:

- ComfyUI setup or configuration
- Image generation service
- Stable Diffusion workflows
- The comfyui volume or port 8188
- GPU-accelerated AI art

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
