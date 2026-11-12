# Checkrr Configuration Notes

## Current State

Checkrr is configured with a single YAML file mounted into the container:

```yaml
volumes:
  - ./checkrr/checkrr.yaml:/etc/checkrr.yaml:ro
```

The runtime `checkrr.yaml` currently contains API keys for Sonarr, Sonarr Anime, and Radarr, so it is intentionally gitignored. `checkrr.yaml.example` mirrors it without the keys; keep the two in sync by hand.

## Report-only, weekly

checkrr runs **weekly** (`cron: "@weekly"`, Sundays 00:00 UTC) with `process: false` for every arr, so it only records problems.

- Each run hashes every file under `checkpath` and fully checks only new or changed ones (ffprobe, then an ffmpeg decode of the first 15 minutes). A normal run takes a few minutes.
- With `process: true`, checkrr deletes each flagged file through Sonarr/Radarr and triggers a new search. Until 2026-11-12 it ran that way and deleted about 100 files, mostly on false positives:
  - a burst of "File ended prematurely" / invalid EBML on Apr 10–11 that looks like NAS read errors (Cyberpunk: Edgerunners was deleted twice in a row)
  - harmless decoder warnings such as TrueHD `quant_step_size larger than huff_lsbs`, `non monotonically increasing dts` and h264 `co located POCs unavailable`

  Good Blu-ray remuxes and UHD encodes were replaced with other, sometimes worse, releases. Don't turn `process` back on without reviewing what it flags.
- Flagged files are listed in the web UI (`http://homelab:8585`) and at `/api/files/bad`. The list includes the old flags from the destructive period, many of which point to files that no longer exist.

## Discord report (`checkrr-report`)

In report-only mode checkrr sends no notification about bad files: its Discord `reacquire` notice only fires when it deletes something. The `checkrr-report` sidecar (`report.py`) polls the checkrr API every 10 minutes. When a new finished run appears in `/api/stats/historical`, it posts one summary:

- **Orange:** lists each file flagged during that run, with the ffmpeg/ffprobe reason.
- **Green:** "weekly scan clean". A missing weekly post means checkrr or the sidecar stopped.

Details:
- Webhook: the first of `CHECKRR_DISCORD_WEBHOOK_URL`, `GATUS_DISCORD_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL` that Discord accepts. `CHECKRR_DISCORD_MENTION` is added only to posts that list flagged files.
- State: the last reported run is kept in `${DOCKER_DATA}/checkrr-report/last-run.json`. On first start it records the latest run without posting the backlog.
- Repeats: decode errors are reported once, because checkrr stores the file's hash and skips it next time. Probe failures (unreadable file, no audio stream) aren't hashed, so they repeat every week until the file is fixed.
- Preview a past run without posting: `docker compose run --rm checkrr-report --dry-run --run 2026-10-18T01:21:35Z`.

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
