---
name: notebook-templates
description: |
  Starter notebook templates provisioned into the workspace volume at deploy time.
  First data-only candy in the project — no packages, no services, no dependencies.
  Use when working with notebook-templates, data candies, or jupyter initial content.
---

# notebook-templates -- Starter notebook data candy

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | *(none)* |
| Packages | *(none)* |
| Services | *(none)* |
| Volumes | `workspace` -> `/workspace` |
| Data | `data/notebooks` -> `workspace` volume |
| Install files | *(none)* |

## How It Works

This is a **data candy** — the first of its kind in the project. It uses the `data:` field in `charly.yml` to map a directory of files to a named volume:

```yaml
info: "Starter notebook templates for jupyter"

data:
  - src: data/notebooks
    volume: workspace
```

At build time, the contents of `data/notebooks/` are staged into `/data/workspace/` inside the box.

At deploy time, when the volume is configured as a bind mount (`charly config --bind workspace`), `charly config` copies the staged data from the box into the host-backed volume directory. This seeds the volume with starter content (e.g., `getting-started.ipynb`).

## Included Data

| File | Purpose |
|------|---------|
| `getting-started.ipynb` | Starter notebook for new jupyter deployments |

## Usage

```yaml
# charly.yml
jupyter:
  candy:
    - notebook-templates
    # ... other candies
```

```bash
# Deploy with bind-backed workspace volume
charly config jupyter --bind workspace

# Data is copied from image to host volume on first config
charly start jupyter
```

## Used In Boxes

- `/charly-jupyter:jupyter`
- `/charly-jupyter:jupyter-ml`
- `/charly-jupyter:jupyter-ml-notebook`

## Related Skills

- `/charly-image:layer` -- data field documentation and candy authoring rules
- `/charly-core:charly-config` -- data provisioning during `charly config` setup
- `/charly-core:deploy` -- volume backing configuration (bind, named, encrypted)
- `/charly-jupyter:jupyter` -- the JupyterLab candy that consumes the workspace volume
- `/charly-jupyter:jupyter` -- the box that includes this candy

## When to Use This Skill

Use when the user asks about:

- The notebook-templates candy or its contents
- Data candies and the `data:` field in `charly.yml`
- How starter content gets provisioned into volumes
- The `getting-started.ipynb` notebook
- How `charly config` seeds bind-backed volumes with box data

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
