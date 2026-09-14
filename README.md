# gh-bundle

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/jjoseph456/gh-bundle/actions/workflows/test.yml/badge.svg)](https://github.com/jjoseph456/gh-bundle/actions/workflows/test.yml)

A `gh` CLI extension that does a fast, read-only **first-look triage** of a
GitHub Enterprise Server (GHES) support bundle.

Most first looks at a bundle are `grep -ri error`. That finds noise and misses
the failures that actually take an appliance down. CodeQL, Dependabot, Actions,
and Pages rarely fail on their own inside GHES — they get **starved** by the
appliance underneath them, or cut off from GitHub.com by a corporate proxy.
`gh-bundle` reads the files that show that and flags them in one pass:

- **Disk** filesystems at/above a threshold (default 85%) from `metadata/diagnostics.txt`.
- **Memory** pressure: an estimate from the `free` line, plus the unambiguous
  signal — the kernel **OOM killer** firing in `system-logs/kern.log`, and
  `OOMKilled` in `docker/container-logs/`.
- **Failed services**: non-passing checks in `metadata/services_consul_status.json`.
- **The air-gapped / proxy reality check**: TLS / proxy / GitHub Connect /
  advisory-sync errors in `github-logs/exceptions.log` and `production.log`
  (the usual reason Dependabot "stops working" on GHES is the network, not the engine).
- **ghe-probe** automated findings, if the bundle carried them.

It is **topology-aware** (handles single-node and multi-node/cluster bundles)
and **defensive**: it never assumes a file exists, one corrupt node never aborts
the others, and it labels every estimate as an estimate. It does not modify the
bundle and makes no network calls.

**v2 adds:** selective extraction (only the handful of diagnostic files are
unpacked, never the multi-GB git/Elasticsearch data), strictly-anchored OOM
detection (won't false-positive on app logs that merely mention "out of
memory"), bounded scanning of huge logs, `--json` output for Slack/ticket/CI
hooks, severity color, and meaningful exit codes.

> First-look screen, not a verdict. Every flag points at the source file it came
> from. Confirm the value there before you put it in front of a customer.

## Install

```
gh extension install jjoseph456/gh-bundle
```

Or run it straight from a clone:

```
git clone https://github.com/jjoseph456/gh-bundle
./gh-bundle/gh-bundle <bundle.tgz>
```

## Usage

```
gh bundle <path-to-bundle.tgz | path-to-extracted-dir> [--threshold N] [--json] [--keep]
```

Examples:

```
gh bundle ./support-bundle-2026-02-12.tar.gz
gh bundle ./extracted-bundle --threshold 90
gh bundle ./bundle.tgz --json        # structured output for automation
gh bundle ./bundle.tgz --keep        # leave the temp extraction in place
```

Options:

| Option         | Meaning |
| -------------- | ------- |
| `--threshold N`| Percent at/above which disk and memory are flagged. Default `85`. |
| `--json`       | Emit structured JSON (for Slack/ticket/CI hooks). Disables color. |
| `--keep`       | Keep the temp extraction dir and print its path. |
| `--version`    | Print version and exit. |
| `-h, --help`   | Show help. |

## Exit codes

So it composes into automated triage / CI pipelines:

| Code | Meaning |
| ---- | ------- |
| `0`  | No flags — clean first-look. |
| `2`  | One or more flags raised (resource/service/connectivity). |
| `1`  | Usage, extraction, or script error. |

## JSON output

`--json` emits a structured object: `topology`, `threshold_pct`, `flags`,
`verdict`, `exit_code`, and `nodes[]` each with a `findings[]` array of
`{severity, type, message, source}`. Pipe it straight into `jq`, a Slack/Teams
alert, or a ticket automation. Color is automatically disabled (also when output
is not a TTY, and when `NO_COLOR` is set).

## What it reads (and what it doesn't)

It only opens these paths, relative to each node root (`metadata/...` for
single-node, `<hostname>/metadata/...` for multi-node):

- `metadata/diagnostics.txt` — disk (`df`), memory (`free`), load, release
- `metadata/system.json` — hardware specs (referenced for context)
- `metadata/services_consul_status.json` — service health
- `system-logs/kern.log` — OOM killer
- `docker/container-logs/*` — container OOM
- `github-logs/exceptions.log`, `github-logs/production.log` — TLS/proxy/Connect
- `ghe-probe/ghe-probe-*.md` — automated findings (flagged for you to read)

Bundle layout handling uses defensive path discovery for both single-node and
multi-node archives. Missing or malformed diagnostic files are reported or
skipped without preventing analysis of the remaining bundle.

## Why this exists

Product-level symptoms can originate in the appliance layer. This tool helps
separate resource, service-health, and connectivity signals from the feature
being investigated before an issue is escalated as a product defect.

## Limitations

- The memory percentage from the `free` line is an **estimate** (free's column
  layout varies). The OOM-killer count is the reliable starvation signal.
- It does not parse IOPS/throughput time series; for sustained disk-latency
  questions, go to the diagnostics performance sections / Performance Lab.
- It is a screen, not a diagnosis. It points you at the right file fast; it does
  not replace reading it.

## Development

Run the focused syntax and regression checks:

```bash
bash -n gh-bundle
bash tests/test-gh-bundle.sh
```

For a security issue, use GitHub's private vulnerability reporting feature.
