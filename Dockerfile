FROM ubuntu:22.04
ENV LC_ALL=ja_JP.UTF-8
ENV LANGUAGE=ja_JP.UTF-8
ENV LANG=ja_JP.UTF-8

RUN apt update && apt -y upgrade &&   apt -y install   \
  language-pack-ja-base   language-pack-ja   \
	curl   wget   fish   lv   gh   mutt   mosh   \
	vim   w3m-img   docker   golang   git   autoconf   \
	libtool   autotools-dev   automake   libevent-dev   \
	libncurses-dev   bison   libevent-dev   libevent-2.1-7   \
	libncurses-dev   make   libtool   libssl-dev   bison   \
	byacc   libsixel-bin   libsixel-dev   screen   pkg-config   \
	fzf   python3-pip   python3-saneyaml   ruby   \
	shellcheck   ripgrep   zoxide   yamllint
RUN locale-gen ja_JP.UTF-8
RUN pip3 install PyYAML &&\
  pip3 install pynvim &&\
	pip3 install setuptools
RUN apt update && apt -y upgrade &&\
  DEBIAN_FRONTEND=noninteractive   apt -y install\
	lxde   tigervnc-standalone-server   tigervnc-common   novnc   websockify
RUN echo \"export LANG=ja_JP.UTF-8\" >> ~/.bashrc
RUN useradd -u 503 -g 20 jp30943 -d /home
RUN apt update && apt -y upgrade &&   apt -y install   \
  jq \
  trash-cli \
  tig \
  ripgrep \
  python3.10-venv \
  dnsutils
RUN yes | unminimize
RUN apt -y install man-db manpages-ja manpages-ja-dev
