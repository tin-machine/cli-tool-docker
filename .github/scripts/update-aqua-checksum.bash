#!/usr/bin/env bash
set -euo pipefail

if [ "${RENOVATE_AQUA_CHECKSUM_FORCE:-}" != "1" ] && \
    git diff --quiet -- aqua.yaml && \
    git diff --cached --quiet -- aqua.yaml; then
    echo "aqua.yaml was not changed; skip aqua-checksums.json update"
    exit 0
fi

aqua_version="${AQUA_VERSION:-v2.48.2}"

case "$(uname -s)" in
    Linux)
        aqua_os="linux"
        ;;
    Darwin)
        aqua_os="darwin"
        ;;
    *)
        echo "unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64 | amd64)
        aqua_arch="amd64"
        ;;
    aarch64 | arm64)
        aqua_arch="arm64"
        ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -sSfL -o "$tmp_dir/aqua.tar.gz" \
    "https://github.com/aquaproj/aqua/releases/download/${aqua_version}/aqua_${aqua_os}_${aqua_arch}.tar.gz"
tar -xzf "$tmp_dir/aqua.tar.gz" -C "$tmp_dir" aqua

AQUA_CONFIG=aqua.yaml "$tmp_dir/aqua" update-checksum -prune
