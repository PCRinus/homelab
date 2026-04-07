# Checkrr Configuration Notes

## Current State

Checkrr is configured with a single YAML file mounted into the container:

```yaml
volumes:
  - ./checkrr/checkrr.yaml:/etc/checkrr.yaml:ro
```

The runtime `checkrr.yaml` currently contains API keys for Sonarr, Sonarr Anime, and Radarr, so it is intentionally gitignored.

## Secret Handling Research

Configarr supports the `!secret` YAML tag and a separate `secrets.yml` file, which lets us commit `config.yml` while keeping API keys in an encrypted/gitignored secrets file.

Checkrr appears to use a single config file model. Its documented Docker setup mounts one `checkrr.yaml` file at `/etc/checkrr.yaml`, and the upstream example keeps API keys directly in that config structure. I did not find documented support for Configarr-style `!secret` references, config includes, or a separate `secrets.yml` file.

## Recommended Future Pattern

If we want to commit the Checkrr config safely, use a generated runtime config:

1. Commit a non-secret template, for example `checkrr.yaml.template`.
2. Store API keys in `media-server/checkrr/secrets.yml`.
3. Add `media-server/checkrr/secrets.yml` to the existing SOPS workflow.
4. Add a small render step that combines the template and secrets into the gitignored runtime `checkrr.yaml`.
5. Keep Compose mounting the generated `checkrr.yaml` into `/etc/checkrr.yaml`.

This preserves the current Checkrr runtime behavior while matching the repo's secret-management pattern as closely as Checkrr allows.
