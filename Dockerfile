FROM ubuntu:24.04 AS neovim-build
# neovimのmake時に DCMAKE_INSTALL_PREFIX を付けている理由
# マルチステージビルドを行う際に、/usr/local配下にインストールすると、どのファイルをCPOYすべきか完全に把握しづらいため
# (/opt/neovim配下にまとまっているとCOPYで扱いやすい)
# gettext はmakeの前にインストールされている必要がある
# 	git gettext shfmt ninja-build gettext cmake unzip curl luajit libluajit-5.1-dev && \
RUN apt-get update && apt-get -y install \
	git gettext shfmt ninja-build gettext cmake unzip curl && \
  git clone https://github.com/neovim/neovim.git && \
  cd neovim && git fetch origin && git checkout release-0.10 && \
 	make -j$(nproc) CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/opt/neovim" && \
 	make install

FROM ubuntu:24.04 AS lazygit
RUN apt-get update && apt-get -y install curl \
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*') \
  curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
  tar xf lazygit.tar.gz lazygit

# FROM ubuntu:24.04 AS terraform-install
# # teraformインストール
# # 下記の方法だとlsb_releaseでエラーが起きるのでバイナリをダウンロードする
# # 	wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
# # 	echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list && \
# # 	apt-get update && apt install terraform && \
# # https://developer.hashicorp.com/terraform/install
# RUN	apt-get update && apt-get -y install curl unzip && \
#   curl -L https://releases.hashicorp.com/terraform/1.7.1/terraform_1.7.1_linux_arm64.zip -o terraform.zip && \
#   unzip terraform.zip

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=ja_JP.UTF-8
ENV LANGUAGE=ja_JP.UTF-8
ENV LANG=ja_JP.UTF-8

# Neovimとその依存ファイルをコピー
COPY --from=neovim-build /opt/neovim /opt/neovim
# COPY --from=terraform-install /terraform /usr/local/bin/
COPY --from=lazygit lazygit /usr/local/bin/lazygit

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
  yes | unminimize && \
	apt-get -y install \
	  language-pack-ja-base \
	  language-pack-ja && \
	  locale-gen ja_JP.UTF-8 && \
        apt-get -y install \
	  ansible \
	  bat \
	  cargo \
	  composer \
	  curl \
	  dnsutils \
	  fd-find \
	  fish \
	  fzf \
	  gh \
	  git \
	  golang \
	  gosu \
	  hugo \
	  iproute2 \
	  iputils-ping \
	  jq \
	  libsixel-bin \
	  lv \
	  luarocks \
	  mutt \
	  mosh \
	  ripgrep \
	  man-db \
	  manpages-ja \
	  manpages-ja-dev \
	  net-tools \
	  node-typescript \
	  openjdk-11-jre \
	  passwd \
	  php \
	  python3-full \
	  python3-pip \
	  python3-pynvim \
	  ripgrep \
	  ruby \
	  screen \
	  shellcheck \
	  sudo \
	  terraform-switcher \
	  tmux \
	  tig \
	  trash-cli \
	  tree \
	  w3m-img \
	  wget \
	  yamllint \
	  zoxide \
	  make \
	  cmake && \
        cargo install stylua && \
  	apt-get update && \
	apt-get -y upgrade && \
	apt-get clean && \
  	rm -rf /var/lib/apt/lists/* && \
  	curl -L "https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl" -o /usr/local/bin/kubectl && \
  	chmod +x /usr/local/bin/kubectl

# neovimに必要なパッケージと gcc-11のシンボリックリンクを作成している
# 下記のエラーが出るため
#  Failed to source `/Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim`
#
#  vim/_editor.lua:0: BufReadPost Autocommands for "*"..script nvim_exec2() called at BufReadPost Autocommands for "*":0../Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim, line 45: Vim(lua):No C compiler found! "gcc -11" are not executable.
RUN	cd /usr/bin/ && ln -s gcc-13 gcc-11

RUN	curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  sudo ./aws/install && \
	rm -rf aws

RUN apt-get -y remove neovim

# エントリーポイントスクリプトのコピー
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# エントリーポイントの設定
ENTRYPOINT ["stdbuf", "-oL", "/usr/local/bin/entrypoint.sh"]

# デフォルトのコマンド
CMD ["bash", "-l"]
