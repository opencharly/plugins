---
name: google-cloud
description: |
  Google Cloud SDK providing gcloud, gsutil, and bq CLI tools.
  Use when working with Google Cloud Platform, GCP services, or cloud SDK configuration.
---

# google-cloud -- Google Cloud SDK

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `task:` |

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - google-cloud
```

## Used In Boxes

- (none currently enabled)

## Related Candies

- `/charly-coder:google-cloud-npm` -- additional GCP npm tools (firebase-tools, gemini-cli)

## When to Use This Skill

Use when the user asks about:

- Google Cloud SDK installation
- gcloud, gsutil, or bq commands
- GCP authentication or configuration
- Google Cloud Platform services

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, env_provide, tests block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block
