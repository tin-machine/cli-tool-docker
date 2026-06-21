# Install Method Reference

Use this reference after reading `SKILL.md`.

The goal is to add one CLI tool to `cli-tool-docker` with the least surprising long-term maintenance path.

## Current repository pattern

`Dockerfile` uses these installation styles:

| Route | Current examples | Use when |
| --- | --- | --- |
| Ubuntu apt in `base` | `ansible`, `bat`, `docker.io`, `ffmpeg`, `gh`, `jq`, `ripgrep`, `shellcheck`, `tmux`, `yamllint` | Ubuntu 26.04 package is acceptable and version freshness is not critical |
| `aqua.yaml` in `tools` | `uv`, `aws-cli`, `lambroll`, `golangci-lint`, `helm`, `kubectl`, `yq`, `tenv`, `ghq` | Tool is in aqua registry and should be pinned, checksummed, and Renovate-managed |
| Source build stage | Neovim `release-0.11`, tmux with sixel | Required feature is unavailable from apt/prebuilt package |
| Prebuilt release archive | `lazygit`, `nerdctl-full`, CNI plugins, `osc`, `yazi`, `stylua`, `lychee` | Upstream releases provide good Linux binaries but aqua is unsuitable or custom install layout is needed |
| `.deb` download | Chawan amd64 package | Upstream publishes a Debian package and arch support is limited |
| Volta/npm global | `@anthropic-ai/claude-code`, `@google/gemini-cli`, `@openai/codex`, `markdownlint-cli` | Tool is Node-based and intended as a global CLI |
| cargo install | `navi`, `zoxide` | Rust CLI needs cargo install and prebuilt/aqua route is not chosen |
| gem/luarocks | `ruby-lsp`, `rubocop`, `erb_lint`, `luacheck` | Tool belongs to Ruby/Lua development workflow |

## Selection checklist

Answer these in order. Stop at the first strong match.

1. Is the command already installed?

```bash
rg -n "command-name|project-name" Dockerfile aqua.yaml README.md renovate.json
```

If yes, update the existing route instead of adding a new one.

2. Is it in Ubuntu 26.04 apt and version does not matter much?

Use apt in the `base` stage. Add the package to the existing apt list. Keep the list readable and do not introduce a separate `RUN apt-get install` for one tool unless isolation is necessary.

3. Is it in aqua registry?

Use `aqua.yaml` when the tool is a GitHub-style released CLI and aqua supports the package. Prefer this for Kubernetes, Terraform, AWS, lint, and standalone Go/Rust CLIs when registry support is good.

4. Is it a Node CLI?

Use the existing Volta block if it should be available globally and can be installed by package name. Pinning may be indirect depending on npm package behavior, so mention that if version reproducibility matters.

5. Is it a language ecosystem developer tool?

Use the existing cargo, gem, or luarocks block only if that ecosystem is the natural source. Do not use cargo merely because a Rust tool exists if aqua provides a cleaner pinned binary.

6. Does upstream publish a Linux binary archive?

Use a Dockerfile prebuilt install. Add an `ARG TOOL_VERSION=...`, handle `TARGETARCH`, verify checksum when feasible, install into `/usr/local/bin` or `/opt/<tool>`, and remove temporary files in the same `RUN`.

7. Does the tool require compile-time options or a specific branch?

Use a dedicated source-build stage. Copy only the result into `artifacts` or `final`.

## apt route

Use apt for broad, boring OS packages.

Good fits:

- libraries and support commands used by multiple tools
- stable utilities where Ubuntu version is acceptable
- packages that are easier to maintain through Ubuntu security updates

Avoid apt when:

- the Ubuntu package is too old for the user's workflow
- the tool is already in aqua with good release support
- the package drags in a very large runtime that the user has not accepted

Edit pattern:

```Dockerfile
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
      existing-package \
      new-package \
      another-package && \
    rm -rf /var/lib/apt/lists/*
```

## aqua route

Use aqua for pinned standalone CLIs.

Edit pattern:

```yaml
packages:
  - name: owner/repo@v1.2.3
```

After editing, checksum maintenance is required:

```bash
aqua update-checksum -prune
```

If the user did not ask for validation or command execution, do not run it automatically. Report that it remains to be run.

## prebuilt archive route

Use this when the release asset names, install layout, or architecture behavior need custom handling.

Required pattern:

```Dockerfile
ARG TOOL_VERSION=v1.2.3
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) TOOL_ARCH=x86_64 ;; \
      arm64) TOOL_ARCH=aarch64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/tool.tar.gz "https://example.invalid/tool-${TOOL_VERSION}-${TOOL_ARCH}.tar.gz"; \
    echo "<sha256>  /tmp/tool.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/tool.tar.gz -C /tmp; \
    install -m0755 /tmp/tool /usr/local/bin/tool; \
    rm -rf /tmp/tool /tmp/tool.tar.gz
```

If a checksum is not available, say so explicitly in the response and explain the risk. Prefer finding a checksum or using aqua instead.

## source-build route

Use this only when necessary.

Required pattern:

- Add a named build stage.
- Install build dependencies in the build stage, not in final unless needed at runtime.
- Pin branch, tag, or commit when possible.
- Install into `/opt/<tool>` or `/out`.
- Copy only runtime artifacts into the `artifacts` stage or final image.

Example shape:

```Dockerfile
FROM build AS tool-build
WORKDIR /build/tool
RUN git clone https://github.com/example/tool.git . && \
    git checkout v1.2.3 && \
    make -j"$(nproc)" && \
    make install PREFIX=/out
```

## README and external docs

Update `README.md` only when the new tool changes user-visible behavior, architecture support, build instructions, or known tradeoffs.

If Hugo docs under `/home/kaoru/ghq/github.com/tin-machine/hugo/content` contain the canonical explanation, do not duplicate large text in README. Report a proposed Hugo doc update if it is outside the repo or not requested.

Known relevant docs from the current workspace include:

- `/home/kaoru/ghq/github.com/tin-machine/hugo/content/docker/docker-common.md`
- `/home/kaoru/ghq/github.com/tin-machine/hugo/content/docker/docker-ubuntu-26-04-cli-tool-docker.md`
- `/home/kaoru/ghq/github.com/tin-machine/hugo/content/docker/docker-image-size-cli-tool-docker.md`
- `/home/kaoru/ghq/github.com/tin-machine/hugo/content/docker/cli-tool-container-user-mapping.md`

## Response template

Use this template for final replies:

```text
選択した導入経路: <apt|aqua|prebuilt|source-build|Volta|cargo|gem|luarocks>
理由: <one or two concrete reasons>
変更ファイル: <files>
未実行の確認: <commands or none>
ドキュメント更新候補: <paths or none>
次に行うなら: <next action>
```
