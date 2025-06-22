FROM ubuntu:25.04 AS build-base
RUN apt-get update && \
    apt-get -y install \
      autoconf \
      automake \
      bison \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      git \
      gettext \
      libevent-dev \
      libssl-dev \
      libxcb-shape0-dev \
      libxcb-xfixes0-dev \
      jq \
      ncurses-dev \
      ninja-build \
      shfmt \
      tar \
      pkg-config \
      unzip

# neovimのmake時に DCMAKE_INSTALL_PREFIX を付けている理由
# マルチステージビルドを行う際に、/usr/local配下にインストールすると、どのファイルをCPOYすべきか完全に把握しづらいため
# (/opt/neovim配下にまとまっているとCOPYで扱いやすい)
# gettext はmakeの前にインストールされている必要がある
#  git gettext shfmt ninja-build gettext cmake unzip curl luajit libluajit-5.1-dev && \
FROM build-base AS neovim-build
RUN git clone https://github.com/neovim/neovim.git && \
    cd neovim && \
    git fetch origin && \
    git checkout release-0.11 && \
    make -j$(nproc) VERBOSE=1 CMAKE_BUILD_TYPE=Release CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/opt/neovim" && \
    make install

FROM build-base AS tmux-build
WORKDIR /build
RUN git clone https://github.com/tmux/tmux.git && \
    cd tmux && \
    sh autogen.sh && \
    ./configure --enable-sixel --prefix=/opt/tmux && \
    make -j$(nproc) && \
    make install

FROM build-base AS lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*') && \
    if [ -z "$LAZYGIT_VERSION" ]; then echo "Failed to get lazygit version"; exit 1; fi && \
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" && \
    tar xf lazygit.tar.gz lazygit

# yazi のインストール
FROM build-base AS yazi
# Rustのインストール（指定パスで）
ENV CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path && \
    /opt/cargo/bin/cargo install yazi-fm && \
    /opt/cargo/bin/yazi --version

FROM build-base AS nerdctl-install
# nerdctl のアーキテクチャ判定とインストール
RUN set -euo pipefail && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) ARCH="amd64" ;; \
      aarch64) ARCH="arm64" ;; \
      armv7l) echo "⚠️  armv7l is not supported by nerdctl-full. Exiting." && exit 1 ;; \
      *) echo "❌ Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    OS="linux" && \
    echo "🔍 Fetching latest nerdctl version..." && \
    LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | jq -r .tag_name) && \
    echo "LATEST_VERSION is ${LATEST_VERSION}" && \
    FILENAME="nerdctl-full-${LATEST_VERSION#v}-${OS}-${ARCH}.tar.gz" && \
    URL="https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${FILENAME}" && \
    TMPDIR=$(mktemp -d) && \
    echo "📁 Created temp directory: $TMPDIR" && \
    cd "$TMPDIR" && \
    echo "📦 Downloading $FILENAME..." && \
    curl -LO "$URL" && \
    echo "📂 Extracting archive..." && \
    tar -xzf "$FILENAME" && \
    echo "🚀 Installing nerdctl to /usr/local/bin/..." && \
    cp ./bin/* /usr/local/bin/ && \
    cd / && rm -rf "$TMPDIR"

FROM build-base AS cni-install
ARG CNI_VERSION=v1.3.0
# アーキテクチャ判定とCNIプラグインのダウンロード＆展開
RUN set -euo pipefail && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) ARCH="amd64" ;; \
      aarch64) ARCH="arm64" ;; \
      armv7l) echo "❌ armv7l は CNI plugins が未サポートです。exit 0します" && exit 0 ;; \
      *) echo "❌ Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    OS="linux" && \
    URL="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-${OS}-${ARCH}-${CNI_VERSION}.tgz" && \
    INSTALL_DIR="/opt/cni/bin" && \

    mkdir -p "$INSTALL_DIR" && \
    echo "📁 Installing CNI plugins to $INSTALL_DIR from $URL" && \
    curl -L "$URL" | tar -xz -C "$INSTALL_DIR" && \
    ls -1 "$INSTALL_DIR"

FROM build-base AS go-cli-install
ARG GHQ_VERSION=v1.8.0
ARG OSC_VERSION=v0.4.8
RUN set -euo pipefail && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) ARCH="amd64" ;; \
      aarch64) ARCH="arm64" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    OS=linux && \
# ghqインストール
    FILENAME="ghq_${OS}_${ARCH}.zip" && \
    URL="https://github.com/x-motemen/ghq/releases/download/${GHQ_VERSION}/${FILENAME}" && \
    curl -sSL "$URL" -o ghq.zip && \
    unzip ghq.zip && \
    mv ghq_linux_${ARCH}/ghq /usr/local/bin/ghq && \
    chmod +x /usr/local/bin/ghq && \
    rm ghq.zip && \
# OSC52を使ってコピーアンドペーストできるコマンドを追加
    FILENAME="osc_Linux_${ARCH}.tar.gz" && \
    curl -L "https://github.com/theimpostor/osc/releases/download/${OSC_VERSION}/${FILENAME}" \
      -o osc.tar.gz && \
    tar -xzf osc.tar.gz -C /tmp && \
    mv /tmp/osc /usr/local/bin/osc && \
    chmod +x /usr/local/bin/osc && \
    rm osc.tar.gz

FROM ubuntu:25.04
ENV DEBIAN_FRONTEND=noninteractive \
    CLOUDSDK_INSTALL_DIR=/usr/local/google-cloud-sdk \
    AQUA_VERSION=v2.48.2 \
    AQUA_GLOBAL_CONFIG=/usr/local/etc/aqua.yaml \
    AQUA_ROOT_DIR=/usr/local/aqua \
    PATH="/usr/local/aqua/bin:\
/usr/local/google-cloud-sdk/google-cloud-sdk/bin/:\
/opt/neovim/bin:\
/opt/tmux/bin:\
/opt/cni/bin:\
/opt/npm-global/bin:\
$PATH"

# aquaの設定ファイルをコピー
COPY aqua.yaml /usr/local/etc/

# Docker Buildx がサポートするアーキテクチャを指定
ARG TARGETARCH

# unminimizeしている理由としては、manページ、ロケールを追加したいため
# locale-gen は language-pack-ja, language-pack-ja-base の後に実行する
# 以下は :checkhealth でのワーニングへの対応
# mason.nvim: openjdk-11-jre, php, npm
# neoconf.nvim
#   jsonc の解決方法がわからない
#   WARNING **TreeSitter jsonc** parser is not installed. Highlighting of jsonc files might be broken
#   WARNING **lspconfig jsonls** is not installed? You won't get any auto completion in your settings files
# WARNING tree-sitter executable not found (parser generator, only needed for :TSInstallFromGrammar, not required for :TSInstall)
#   :TSInstallFromGrammar を実行する
RUN apt-get update && \
    apt-get -y install \
      language-pack-ja \
      language-pack-ja-base \
      locales \
      tzdata && \
    locale-gen ja_JP.UTF-8 && \
    apt-get -y install \
      ansible \
      bat \
      cargo \
      cmake \
      composer \
      curl \
      direnv \
      dnsutils \
      docker.io \
      docker-compose-v2 \
      fd-find \
      fish \
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
      screen \
      shellcheck \
      sqlite3 \
      strace \
      sudo \
      terraform-switcher \
      texlive-latex-base \
      texlive-latex-recommended \
      texlive-fonts-recommended \
      tmux \
      tig \
      trash-cli \
      tree \
      w3m-img \
      wget \
      yamllint \
      zoxide && \
# juliaのインストール
    curl -fsSL https://install.julialang.org | \
    sh -s -- --yes --path "/usr/local/julia" && \
    /usr/local/julia/bin/juliaup add release && \
# Google Cloud SDKのインストール
    curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=${CLOUDSDK_INSTALL_DIR} && \
# 独自のビルドオプションを付けたものをCOPYするので
# 既存のパッケージからインストールしたものは削除する
    apt-get -y remove neovim neovim-runtime tmux && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    cargo install stylua && \
# neovimに必要なパッケージと gcc-11のシンボリックリンクを作成している
# 下記のエラーが出るため
#  Failed to source `/Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim`
#
#  vim/_editor.lua:0: BufReadPost Autocommands for "*"..script nvim_exec2() called at BufReadPost Autocommands for "*":0../Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim, line 45: Vim(lua):No C compiler found! "gcc-11" are not executable.
    cd /usr/bin/ && ln -s gcc-13 gcc-11 && \
# aquaのインストール
    curl -sSfL -o aqua.tar.gz "https://github.com/aquaproj/aqua/releases/download/${AQUA_VERSION}/aqua_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf aqua.tar.gz -C /usr/local/bin aqua && \
    rm aqua.tar.gz && \
    cd /usr/local/etc/ && \
    aqua install && \
# npmのパッケージを /opt/npm-global にインストール
    mkdir -p /opt/npm-global && \
    npm config set prefix '/opt/npm-global' && \
    echo 'prefix=/opt/npm-global' >> /etc/npmrc && \
    echo 'export PATH=/opt/npm-global/bin:$PATH' > /etc/profile.d/npm-global.sh && \
    chmod +x /etc/profile.d/npm-global.sh && \
    npm install -g @anthropic-ai/claude-code

# Neovimとその依存ファイルをコピー
COPY --from=neovim-build /opt/neovim /opt/neovim
COPY --from=tmux-build /opt/tmux /opt/tmux
COPY --from=nerdctl-install /usr/local/bin/ /usr/local/bin/
COPY --from=lazygit lazygit /usr/local/bin/lazygit
COPY --from=cni-install /opt/cni /opt/cni
COPY --from=yazi /opt/cargo /opt/cargo
COPY --from=yazi /opt/rustup /opt/rustup
COPY --from=go-cli-install /usr/local/bin/ghq /usr/local/bin/ghq
COPY --from=go-cli-install /usr/local/bin/osc /usr/local/bin/osc

# エントリーポイントの設定
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# デフォルトのコマンド
# CMD ["bash", "-l"]
CMD ["tail", "-F", "/dev/null"]
