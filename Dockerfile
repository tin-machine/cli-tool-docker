# =========================
# Common base
# =========================
FROM ubuntu:26.04 AS base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# Buildx がサポートするアーキテクチャ
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=ja_JP.UTF-8 \
    LC_ALL=ja_JP.UTF-8 \
    TZ=Asia/Tokyo

RUN apt-get update && \
    apt-get -y --no-install-recommends install \
      language-pack-ja language-pack-ja-base locales tzdata && \
    locale-gen ja_JP.UTF-8 && \
    apt-get -y --no-install-recommends install \
      ansible \
      ansible-lint \
      bat \
      binutils \
      bubblewrap \
      build-essential \
      cabextract \
      cargo \
      chafa \
      cmake \
      composer \
      ca-certificates \
      curl \
      direnv \
      bind9-dnsutils \
      docker.io \
      docker-compose-v2 \
      eza \
      fd-find \
      ffmpeg \
      file \
      fish \
      fortune-mod \
      fzf \
      gh \
      ghostscript \
      git \
      golang \
      golang-docker-credential-helpers \
      gosu \
      grim \
      hugo \
      imagemagick \
      inotify-tools \
      innoextract \
      iproute2 \
      iputils-ping \
      jq \
      latexmk \
      libarchive-tools \
      libxcb-shape0 \
      libxcb-xfixes0 \
      libmysqlclient-dev \
      libsixel-bin \
      lv \
      luarocks \
      make \
      mesa-utils \
      mutt \
      msitools \
      mosh \
      mupdf-tools \
      mysql-client \
      net-tools \
      nmap \
      nkf \
      openjdk-21-jdk \
      7zip \
      7zip-rar \
      passwd \
      php \
      pkg-config \
      poppler-utils \
      python3-full \
      python3-pip \
      python3-pynvim \
      pipx \
      qpdf \
      rbenv \
      resvg \
      ripgrep \
      rsync \
      ruby \
      ruby-dev \
      screen \
      shellcheck \
      slurp \
      scrot \
      sqlite3 \
      strace \
      sudo \
      tcpdump \
      tar \
      texlive-latex-base \
      texlive-latex-recommended \
      texlive-fonts-recommended \
      tshark \
      tmux \
      tig \
      trash-cli \
      tree \
      unshield \
      unzip \
      vulkan-tools \
      w3m-img \
      wget \
      x11-utils \
      xdotool \
      xxd \
      yamllint \
      zstd && \
    rm -rf /var/lib/apt/lists/*

# =========================
# Build toolchain stage
# =========================
FROM base AS build
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
      autoconf \
      automake \
      bison \
      build-essential \
      cmake \
      gettext \
      libevent-dev \
      libssl-dev \
      libxcb-shape0-dev \
      libxcb-xfixes0-dev \
      libncurses-dev \
      ninja-build \
      shfmt \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

# =========================
# Neovim build
# =========================
FROM build AS neovim-build
WORKDIR /build/neovim
RUN git clone https://github.com/neovim/neovim.git . && \
    git fetch origin && \
    git checkout release-0.11 && \
    make -j"$(nproc)" VERBOSE=1 CMAKE_BUILD_TYPE=Release \
      CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/opt/neovim" && \
    make install

# =========================
# tmux build (with sixel)
# =========================
FROM build AS tmux-build
WORKDIR /build/tmux
RUN git clone https://github.com/tmux/tmux.git . && \
    sh autogen.sh && \
    ./configure --enable-sixel --prefix=/opt/tmux && \
    make -j"$(nproc)" && \
    make install

# =========================
# lazygit (arch-aware)
# =========================
FROM build AS lazygit
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG TARGETARCH
RUN VER=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name | sed 's/^v//'); \
    case "$TARGETARCH" in \
      amd64)  A=Linux_x86_64 ;; \
      arm64)  A=Linux_arm64  ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -L -o /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${VER}/lazygit_${VER}_${A}.tar.gz"; \
    mkdir -p /out && tar -xzf /tmp/lazygit.tar.gz -C /out lazygit

# =========================
# navi , zoxide via cargo
# =========================
FROM build AS cargo-install
ENV CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:$PATH
# crates.io の yazi は build.rs で yazi-build 経由のインストールを要求する
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --no-modify-path && \
    /opt/cargo/bin/cargo install navi && \
    /opt/cargo/bin/cargo install zoxide --locked && \
    install -Dm0755 /opt/cargo/bin/navi /out/bin/navi && \
    install -Dm0755 /opt/cargo/bin/zoxide /out/bin/zoxide

# =========================
# nerdctl(full) install (arch-aware)
# =========================
FROM build AS nerdctl-install
ARG TARGETARCH
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
# 作業用ディレクトリを固定で用意して切り替える
WORKDIR /tmp/nerdctl
RUN case "$TARGETARCH" in \
      amd64)  A=amd64 ;; \
      arm64)  A=arm64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    VER=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | jq -r .tag_name); \
    F="nerdctl-full-${VER#v}-linux-${A}.tar.gz"; \
    URL="https://github.com/containerd/nerdctl/releases/download/${VER}/${F}"; \
    curl -LO "$URL"; \
    tar -xzf "$F"; \
    install -d /out/bin; \
    cp -a ./bin/* /out/bin/
# 後片付け（次の命令のためにルートへ戻し、作業ディレクトリを削除）
WORKDIR /
RUN rm -rf /tmp/nerdctl

# =========================
# CNI plugins (arch-aware)
# =========================
FROM build AS cni-install
ARG TARGETARCH
ARG CNI_VERSION=v1.3.0
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
RUN case "$TARGETARCH" in \
      amd64)  A=amd64 ;; \
      arm64)  A=arm64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    URL="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${A}-${CNI_VERSION}.tgz"; \
    mkdir -p /opt/cni/bin; \
    curl -L "$URL" | tar -xz -C /opt/cni/bin; \
    ls -1 /opt/cni/bin

# =========================
# osc52 CLI
# =========================
FROM build AS go-cli-install
ARG TARGETARCH
ARG OSC_VERSION=v0.4.8
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
RUN case "$TARGETARCH" in \
      amd64)  OSC_A=x86_64 ;; \
      arm64)  OSC_A=arm64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -sSL -o /tmp/osc.tar.gz "https://github.com/theimpostor/osc/releases/download/${OSC_VERSION}/osc_Linux_${OSC_A}.tar.gz"; \
    tar -xzf /tmp/osc.tar.gz -C /tmp; \
    install -D /tmp/osc /out/osc

# =========================
# yazi (prebuilt, arch-aware)
# =========================
FROM base AS yazi-install
ARG TARGETARCH
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64)  YAZI_ARCH=x86_64-unknown-linux-gnu ;; \
      arm64)  YAZI_ARCH=aarch64-unknown-linux-gnu ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    URL="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${YAZI_ARCH}.zip"; \
    echo "Fetching: ${URL}"; \
    mkdir -p /tmp/yazi /out/bin /out/share; \
    curl -fL -o /tmp/yazi.zip "${URL}"; \
    unzip -q /tmp/yazi.zip -d /tmp/yazi; \
    ROOT="/tmp/yazi"; \
    if [ -d "/tmp/yazi/yazi-${YAZI_ARCH}" ]; then ROOT="/tmp/yazi/yazi-${YAZI_ARCH}"; fi; \
    if [ -x "${ROOT}/yazi" ]; then install -Dm0755 "${ROOT}/yazi" /out/bin/yazi; fi; \
    if [ -x "${ROOT}/ya" ]; then install -Dm0755 "${ROOT}/ya" /out/bin/ya; fi; \
    if [ -d "${ROOT}/share" ]; then cp -a "${ROOT}/share/." /out/share/; fi

# =========================
# tools stage (集約)
# =========================
FROM base AS tools
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG TARGETARCH

ENV CLOUDSDK_INSTALL_DIR=/usr/local/google-cloud-sdk \
    AQUA_VERSION=v2.48.2 \
    AQUA_GLOBAL_CONFIG=/usr/local/etc/aqua.yaml \
    AQUA_ROOT_DIR=/usr/local/aqua \
    VOLTA_HOME=/opt/volta \
    PATH="/usr/local/aqua/bin:/usr/local/google-cloud-sdk/google-cloud-sdk/bin:/opt/npm-global/bin:/opt/volta/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# gcc-11 参照を回避（必要要件に合わせて）
RUN ln -sf "$(command -v gcc)" /usr/bin/gcc-11

# Google Cloud SDK
RUN curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="${CLOUDSDK_INSTALL_DIR}"

# aqua 本体
COPY aqua.yaml /usr/local/etc/aqua.yaml
COPY aqua-checksums.json /usr/local/etc/aqua-checksums.json
# 作業ディレクトリを切り替えて実行（cd 不要）
WORKDIR /usr/local/etc
RUN curl -sSfL -o /tmp/aqua.tar.gz "https://github.com/aquaproj/aqua/releases/download/${AQUA_VERSION}/aqua_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/aqua.tar.gz -C /usr/local/bin aqua && \
    rm /tmp/aqua.tar.gz && \
    aqua install
# 以降で作業ディレクトリに依存しないなら戻しておくと親切
WORKDIR /

# Volta（公式スクリプトで確実に導入）
RUN curl -fsSL https://get.volta.sh | bash -s -- --skip-setup && \
    mkdir -p "$VOLTA_HOME" && \
    volta install node@v24.2.0 && \
    volta install \
      @anthropic-ai/claude-code \
      @google/gemini-cli \
      @openai/codex \
      clawdbot \
      jsonlint \
      markdownlint-cli && \
    rm -rf /root/.npm /root/.cache/node-gyp

# sops
ARG SOPS_VERSION=v3.8.1
ARG TARGETARCH
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) ARCH=amd64 ;; \
      arm64) ARCH=arm64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${ARCH}"; \
    curl -L "$URL" -o /usr/local/bin/sops; \
    chmod +x /usr/local/bin/sops; \
    /usr/local/bin/sops --version

# lychee link checker
ARG LYCHEE_VERSION=lychee-v0.24.2
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        LYCHEE_ARCH=x86_64-unknown-linux-musl; \
        LYCHEE_SHA256=73657a111819a30c47c08352896796f23d64e4eb2b3ed39b6d32149241566fc5 ;; \
      arm64) \
        LYCHEE_ARCH=aarch64-unknown-linux-gnu; \
        LYCHEE_SHA256=91a7bd65685da41b90ccb9bc867a3d649a7818042dae04ff405e55a25bddee4c ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    LYCHEE_TARBALL="/tmp/lychee.tar.gz"; \
    curl -fsSL -o "$LYCHEE_TARBALL" "https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VERSION}/lychee-${LYCHEE_ARCH}.tar.gz"; \
    echo "${LYCHEE_SHA256}  ${LYCHEE_TARBALL}" | sha256sum -c -; \
    tar -xzf "$LYCHEE_TARBALL" -C /tmp; \
    install -m0755 "/tmp/lychee-${LYCHEE_ARCH}/lychee" /usr/local/bin/lychee; \
    rm -rf "$LYCHEE_TARBALL" "/tmp/lychee-${LYCHEE_ARCH}"; \
    lychee --version

# fff-mcp (AI file-search MCP server)
ARG FFF_MCP_VERSION=v0.9.5
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        FFF_MCP_ARCH=x86_64-unknown-linux-musl; \
        FFF_MCP_SHA256=8e1b0dfbb3b5b05d57b086c3b75c838d283b489b4cadb8636c6b044f29bbe407 ;; \
      arm64) \
        FFF_MCP_ARCH=aarch64-unknown-linux-musl; \
        FFF_MCP_SHA256=67b6a26e24c87ace2cc585ee340c835069fa606e0b36fa87ae066e818ad3bac2 ;; \
      *) \
        echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/dmtrKovalenko/fff.nvim/releases/download/${FFF_MCP_VERSION}/fff-mcp-${FFF_MCP_ARCH}"; \
    curl -fsSL -o /tmp/fff-mcp "${URL}"; \
    echo "${FFF_MCP_SHA256}  /tmp/fff-mcp" | sha256sum -c -; \
    install -Dm0755 /tmp/fff-mcp /usr/local/bin/fff-mcp; \
    rm -f /tmp/fff-mcp

# leaf (markdown previewer)
ARG LEAF_VERSION=1.24.2
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        LEAF_ARCH=x86_64 \
        LEAF_SHA256=b985eefcfd0c4b74d72c0c5d7b9ffa4aec045022b49f09636c2388b57c0ce183 ;; \
      arm64) \
        LEAF_ARCH=arm64 \
        LEAF_SHA256=b2326c0e968b2bc8ce705b555966582c70d41343d4661479e9affa210f2e8641 ;; \
      *) \
        echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/RivoLink/leaf/releases/download/${LEAF_VERSION}/leaf-linux-${LEAF_ARCH}"; \
    curl -fsSL -o /tmp/leaf "${URL}"; \
    echo "${LEAF_SHA256}  /tmp/leaf" | sha256sum -c -; \
    install -Dm0755 /tmp/leaf /usr/local/bin/leaf; \
    rm -f /tmp/leaf

# Chawan TUI browser
ARG CHAWAN_VERSION=0.4.0
ARG CHAWAN_DEB_SHA256=858eb1fb02897a24af4e1d20a17a82692dad100b09ef0064f5f9199e3647dda1
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        CHAWAN_VERSION_DASH="${CHAWAN_VERSION//./-}"; \
        CHAWAN_DEB="/tmp/chawan-${CHAWAN_VERSION}-amd64.deb"; \
        curl -fsSL -o "${CHAWAN_DEB}" "https://git.sr.ht/~bptato/chawan/refs/download/v${CHAWAN_VERSION}/chawan-${CHAWAN_VERSION_DASH}-amd64.deb"; \
        echo "${CHAWAN_DEB_SHA256}  ${CHAWAN_DEB}" | sha256sum -c -; \
        dpkg -i "${CHAWAN_DEB}"; \
        rm -f "${CHAWAN_DEB}"; \
        cha --version; \
        ;; \
      arm64) \
        echo "Chawan ${CHAWAN_VERSION} official binary package is amd64-only; skipping for TARGETARCH=${TARGETARCH}"; \
        ;; \
      *) \
        echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac

# --- Stylua (prebuilt) ---
ARG STYLUA_VERSION=v0.20.0
RUN set -eux; \
    tmpdir="$(mktemp -d)"; \
    trap 'rm -rf "$tmpdir"' EXIT; \
    case "$TARGETARCH" in \
      amd64)  A=x86_64 ;; \
      arm64)  A=aarch64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/JohnnyMorganz/StyLua/releases/download/${STYLUA_VERSION}/stylua-linux-${A}.zip"; \
    echo "Fetching: ${URL}"; \
    curl -fL -o "$tmpdir/stylua.zip" "${URL}"; \
    unzip -q "$tmpdir/stylua.zip" -d "$tmpdir"; \
    install -m0755 "$tmpdir/stylua" /usr/local/bin/stylua

# luacheck / Ruby 開発系
RUN luarocks install luacheck && \
    gem install --no-document ruby-lsp rubocop erb_lint

# =========================
# Runtime artifacts
# =========================
FROM scratch AS artifacts

# Neovim / tmux / nerdctl / lazygit / CNI / cargo-built tools / osc の成果物を集約
COPY --from=neovim-build     /opt/neovim            /opt/neovim
COPY --from=tmux-build       /opt/tmux              /opt/tmux
COPY --from=nerdctl-install  /out/bin/              /usr/local/bin/
COPY --from=lazygit          /out/lazygit           /usr/local/bin/lazygit
COPY --from=cni-install      /opt/cni               /opt/cni
COPY --from=cargo-install    /out/bin/              /usr/local/bin/
COPY --from=go-cli-install   /out/osc               /usr/local/bin/osc
COPY --from=yazi-install     /out/bin/yazi          /usr/local/bin/yazi
COPY --from=yazi-install     /out/bin/ya            /usr/local/bin/ya
COPY --from=yazi-install     /out/share/            /usr/local/share/
COPY --chmod=0755 entrypoint.bash /usr/local/bin/entrypoint.bash

# =========================
# Final runtime image
# =========================
FROM tools AS final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV PATH="/opt/neovim/bin:/opt/tmux/bin:/opt/cni/bin:/opt/bin:${PATH}"

# Ubuntu イメージには UID/GID 1000 の ubuntu ユーザーが含まれる場合がある。
# ホストユーザーと同じ UID/GID のユーザーを entrypoint で作成できるようにし、
# sudo/admin の補助グループを引き継がないよう削除する。
RUN if getent passwd ubuntu >/dev/null; then userdel -r ubuntu; fi && \
    if getent group ubuntu >/dev/null; then groupdel ubuntu; fi

COPY --from=artifacts / /
ENTRYPOINT ["/usr/local/bin/entrypoint.bash"]

# デフォルトのコマンド
CMD ["tail", "-F", "/dev/null"]
