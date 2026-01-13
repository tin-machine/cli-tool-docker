# =========================
# Common base
# =========================
FROM ubuntu:25.04 AS base
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
      bat \
      build-essential \
      cargo \
      chafa \
      cmake \
      composer \
      ca-certificates \
      curl \
      direnv \
      dnsutils \
      docker.io \
      docker-compose-v2 \
      fd-find \
      fish \
      fortune-mod \
      fzf \
      gh \
      ghostscript \
      git \
      golang \
      golang-docker-credential-helpers \
      gosu \
      hugo \
      imagemagick \
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
      mutt \
      mosh \
      mysql-client \
      net-tools \
      nkf \
      openjdk-21-jdk \
      p7zip-full \
      p7zip-rar \
      passwd \
      php \
      python3-full \
      python3-pip \
      python3-pynvim \
      rbenv \
      ripgrep \
      ruby \
      ruby-dev \
      screen \
      shellcheck \
      sqlite3 \
      strace \
      sudo \
      tar \
      texlive-latex-base \
      texlive-latex-recommended \
      texlive-fonts-recommended \
      tmux \
      tig \
      trash-cli \
      tree \
      unzip \
      w3m-img \
      wget \
      yamllint \
      zoxide \
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
      ncurses-dev \
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
# yazi via cargo
# =========================
FROM build AS yazi
ENV CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:$PATH
# crates.io の yazi は build.rs で yazi-build 経由のインストールを要求する
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --no-modify-path && \
    /opt/cargo/bin/cargo install --locked --force yazi-build && \
    /opt/cargo/bin/yazi --version

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
# go cli tools (ghq, osc52)
# =========================
FROM build AS go-cli-install
ARG TARGETARCH
ARG GHQ_VERSION=v1.8.0
ARG OSC_VERSION=v0.4.8
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
RUN case "$TARGETARCH" in \
      amd64)  GHQ_A=amd64; OSC_A=x86_64 ;; \
      arm64)  GHQ_A=arm64; OSC_A=arm64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    # ghq
    curl -sSL -o /tmp/ghq.zip "https://github.com/x-motemen/ghq/releases/download/${GHQ_VERSION}/ghq_linux_${GHQ_A}.zip"; \
    unzip /tmp/ghq.zip -d /tmp; \
    install -D /tmp/ghq_linux_${GHQ_A}/ghq /out/ghq; \
    # osc (OSC52)
    curl -sSL -o /tmp/osc.tar.gz "https://github.com/theimpostor/osc/releases/download/${OSC_VERSION}/osc_Linux_${OSC_A}.tar.gz"; \
    tar -xzf /tmp/osc.tar.gz -C /tmp; \
    install -D /tmp/osc /out/osc

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

# 後続で使う最低限のツールを tools ステージで確実に用意
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
      ca-certificates \
      curl \
      git \
      jq \
      ruby \
      ruby-dev \
      luarocks \
      python3-pip \
      build-essential \
      gcc && \
    rm -rf /var/lib/apt/lists/*

# gcc-11 参照を回避（必要要件に合わせて）
RUN ln -sf /usr/bin/gcc-13 /usr/bin/gcc-11 || true

# Julia
RUN curl -fsSL https://install.julialang.org | sh -s -- --yes --path "/usr/local/julia" && \
    /usr/local/julia/bin/juliaup add release

# Google Cloud SDK
RUN curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="${CLOUDSDK_INSTALL_DIR}"

# aqua 本体
COPY aqua.yaml /usr/local/etc/aqua.yaml
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
      jsonlint \
      markdownlint-cli

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

# --- Stylua (prebuilt) ---
ARG STYLUA_VERSION=v0.20.0
WORKDIR /tmp/stylua
RUN case "$TARGETARCH" in \
      amd64)  A=x86_64 ;; \
      arm64)  A=aarch64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/JohnnyMorganz/StyLua/releases/download/${STYLUA_VERSION}/stylua-linux-${A}.zip"; \
    echo "Fetching: ${URL}"; \
    curl -fL -o stylua.zip "${URL}"; \
    unzip -q stylua.zip; \
    install -m0755 stylua /usr/local/bin/stylua
WORKDIR /
RUN rm -rf /tmp/stylua

# luacheck / Ruby 開発系
RUN luarocks install luacheck && \
    gem install --no-document ruby-lsp rubocop erb_lint

# =========================
# Final runtime image
# =========================
FROM tools AS final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV PATH="/opt/neovim/bin:/opt/tmux/bin:/opt/cni/bin:${PATH}"

# Neovim / tmux / nerdctl / lazygit / CNI / yazi / ghq / osc の成果物を集約
COPY --from=neovim-build     /opt/neovim            /opt/neovim
COPY --from=tmux-build       /opt/tmux              /opt/tmux
COPY --from=nerdctl-install  /out/bin/              /usr/local/bin/
COPY --from=lazygit          /out/lazygit           /usr/local/bin/lazygit
COPY --from=cni-install      /opt/cni               /opt/cni
COPY --from=yazi             /opt/cargo             /opt/cargo
COPY --from=yazi             /opt/rustup            /opt/rustup
COPY --from=go-cli-install   /out/ghq               /usr/local/bin/ghq
COPY --from=go-cli-install   /out/osc               /usr/local/bin/osc

# エントリーポイント
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# デフォルトのコマンド
CMD ["tail", "-F", "/dev/null"]
