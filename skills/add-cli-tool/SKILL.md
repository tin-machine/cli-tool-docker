---
name: add-cli-tool
description: Add or update command line tools in the tin-machine/cli-tool-docker repository. Use when Codex needs to decide whether a tool belongs in Dockerfile apt packages, aqua.yaml, Dockerfile prebuilt downloads, source-build stages, Volta/npm globals, cargo, gem, or luarocks, and then make a safe minimal change for this daily CLI work-container image. Optimized for smaller local models by requiring a fixed investigation order, explicit install-method selection, and conservative edits.
---

# Add CLI Tool

Use this skill only inside the `cli-tool-docker` repository.

This repository builds a large daily-use CLI container. A new tool can be installed by multiple routes. Do not add a tool before classifying the route.

## Fixed workflow

1. Read repository instructions first: `AGENTS.md`.
2. Read the current implementation files once: `README.md`, `Dockerfile`, `aqua.yaml`, `renovate.json`, `.github/renovate-global.json`.
3. Search related documentation before planning:

```bash
rg -n "cli-tool-docker|Dockerfile|aqua|tool|ツール|container|コンテナ" /home/kaoru/ghq/github.com/tin-machine/homecluster-* /home/kaoru/ghq/github.com/tin-machine/hugo/content
```

4. If the search finds relevant Hugo or homecluster docs, use them as context. If the docs need an update but are outside this repository, report the proposed update instead of silently ignoring it.
5. Classify the tool using `references/install-methods.md`.
6. State the selected install method before editing.
7. Edit only the files required for that method.
8. If validation is requested by the user, run only the smallest relevant check. If not requested, do not build the image or run tests.

## Decision rules for small models

Prefer the first matching option in this order:

1. Use `apt-get install` in the `base` stage when Ubuntu 26.04 has a good-enough package and the exact upstream version is not important.
2. Use `aqua.yaml` when the tool is in aqua registry, is a CLI distributed as upstream releases, and version pinning plus checksum management is desired.
3. Use an existing language/package-manager block only when the tool naturally belongs there: Volta/npm, cargo, gem, or luarocks.
4. Use a prebuilt archive or `.deb` in `Dockerfile` when aqua cannot handle it or the install needs custom arch handling.
5. Use a dedicated source-build stage only when a packaged/prebuilt tool is insufficient because custom build flags, branch selection, or unavailable binaries are required.

If two methods both work, choose the method that avoids duplicate installs already present in `Dockerfile` or `aqua.yaml`.

## Required duplicate check

Before editing, check whether the command name or project already appears in:

```bash
rg -n "TOOL_NAME|COMMAND_NAME" Dockerfile aqua.yaml README.md renovate.json
```

Replace `TOOL_NAME` and `COMMAND_NAME` with the real names. If already installed by another route, do not add a second copy unless the user explicitly wants that.

## Edit map

Use this map to keep edits small.

| Method | Files to edit | Follow-up file |
| --- | --- | --- |
| apt package | `Dockerfile` | Usually none |
| aqua package | `aqua.yaml` | `aqua-checksums.json` after checksum update |
| prebuilt binary/archive/deb | `Dockerfile` | `README.md` only if behavior or architecture support matters |
| source build | `Dockerfile` | `README.md` if the reason is non-obvious |
| Volta/npm global | `Dockerfile` | Usually none |
| cargo/gem/luarocks | `Dockerfile` | Usually none |

## Dockerfile conventions

Keep these conventions:

- Use `SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]` behavior already present.
- Keep `TARGETARCH` handling explicit for downloaded binaries.
- For downloaded artifacts, prefer `curl -fsSL`, pinned version `ARG`, checksum verification, and cleanup in the same `RUN`.
- For unsupported architectures, fail clearly or skip explicitly. Do not create a command stub that succeeds without a real binary.
- For source builds, build in a separate stage and copy only installed artifacts into `artifacts` or `final`.
- Do not copy compiler caches, source trees, package-manager caches, or temporary archives into the final image.
- Avoid installing the same command through apt and aqua or through Dockerfile download and aqua.

## aqua conventions

Use `aqua.yaml` for tools from aqua registry.

Rules:

- Always pin a version in `name: owner/repo@version`.
- Keep `checksum.require_checksum: true`.
- After changing `aqua.yaml`, update `aqua-checksums.json` with:

```bash
aqua update-checksum -prune
```

- Renovate is configured to run `.github/scripts/update-aqua-checksum.bash` for package updates, but manual additions still need checksum maintenance when validation is requested.

## Output format

When reporting the result, keep it short:

1. Selected install method and why.
2. Files changed.
3. Any docs that appear stale or should be updated.
4. Validation not run unless the user requested it.
5. Next action you will take if the user wants to continue.
