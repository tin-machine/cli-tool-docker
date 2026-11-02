# cli-tool-docker

通常、macなりLinuxでCLIの作業環境を作成すると環境を壊すリスクが恐ろしい。
コンテナイメージの形で利用すると、カジュアルにアップデートなり、新しいツールの検証ができる。
このため自分が良く使うコマンドを集めたコンテナイメージを作る事にした。

# 利用方法

通常は `shell.bash` から入る。

```bash
./shell.bash
```

`shell.bash` は host 側で `docker` があれば Docker を使い、なければ `sudo nerdctl` を使う。
Linux では既定で `ghcr.io/tin-machine/cli-tool-docker:latest` を使う。
macOS では `cli-tool-docker:latest` がなければ、この repository の Dockerfile から local build する。

## macOS で apple/container を使う

macOS に [apple/container](https://github.com/apple/container)（`container` コマンド）があれば、`shell.bash` は Docker ではなく apple/container を使う。
`CLI_TOOL_RUNTIME=docker ./shell.bash` で Docker に戻せる（`auto` / `docker` / `apple`）。

- イメージは `ghcr.io/tin-machine/cli-tool-docker:latest-arm64` を使い、無ければ pull する。`latest` は amd64 だけなので使わない
  - `latest-arm64` は CI の `build-arm64-workspace` が動作確認を通った main のイメージに付ける
  - 更新は手で行う: `container image pull --platform linux/arm64 ghcr.io/tin-machine/cli-tool-docker:latest-arm64`
  - `container build` は Dockerfile の大きさに上限があり（[apple/container#735](https://github.com/apple/container/issues/735)）、この Dockerfile はそのままではビルドできない
- CPU とメモリは `CLI_TOOL_CPUS`（既定 4）と `CLI_TOOL_MEMORY`（既定 `8G`）で変えられる
- `jq` が必要（コンテナの一覧を JSON で読むため）

Docker のときとの違い：

| 項目 | apple/container |
|---|---|
| `--network host` | 無い。コンテナには vmnet の IP（192.168.64.x）が付く |
| Mac 上のサービスへの接続（0.0.0.0 で待ち受け） | `host.docker.internal` で繋がる。`shell.bash` が起動時に `/etc/hosts` で vmnet のゲートウェイ（192.168.64.1）に向け、`HB_AGENT_URL=http://host.docker.internal:5321` を渡す（host-bridge 用） |
| Mac 上のサービスへの接続（127.0.0.1 だけで待ち受け） | `sudo container system dns create host.container.internal --localhost 203.0.113.113` を一度実行し、`host.container.internal` で繋ぐ。Mac を再起動すると消えるので、届かなければ delete → create をやり直す |
| `--privileged` | 無い。`--cap-add ALL` を付ける |
| docker.sock / containerd.sock | マウントしない。コンテナ内から docker / nerdctl は使えない |
| SSH エージェント | `--ssh` で転送する |

GSA（Global Secure Access）が有効だと、コンテナ内の名前解決が GSA の仮 IP（6.6.x.x）になり、外に出られないことがある。

## Kubernetes workspace の SSH 入口

SSH は `workspace-ssh-sidecar` target の専用 image で受け、CLI container の tmux へ接続する。
CLI と sidecar の `USER_NAME`、`CLI_USER_ID`、`CLI_GROUP_ID` は同じ非 root identity にする。

| Container | 設定・mount |
| --- | --- |
| CLI (`workspace-flat`) | `CLI_WORKSPACE_MODE=1`、`CLI_WORKSPACE_TMUX=1`、`HOME=/work-home`、`CODEX_HOME=/work-state/codex`。home と永続 state volume を mount |
| SSH (`workspace-ssh-sidecar`) | root 所有・mode 0444 または 0400 の `/run/workspace-ssh/authorized_keys` と、永続 host key directory `/work-state/ssh` を mount |
| 共通 | `/run/workspace-tmux` に同じ一時 volume を mount。Kubernetes では `emptyDir` を使う |

CLI は `workspace` session と `fish -l` を起動し、home の fish/tmux 設定を読む。
Pi の状態は `PI_CODING_AGENT_DIR=/work-state/pi` に初期化する。sidecar に home 全体や CLI ツールを mount する必要はない。
接続先は `/run/workspace-tmux/workspace.sock` に固定し、sidecar の tmux client は `-N` で server の誤起動を防ぐ。
SSH 切断後は同じ session に戻り、最後の pane を終了した場合は次回ログインで CLI 側に新しい session を作る。

この入口は対話 SSH 専用で、リモート command と SFTP は提供しない。
Pod / CLI container の再作成で実行中の tmux は失われる。host key と作業ファイルの保持は永続 volume の役割である。
公開 port は sidecar の TCP 22。tailnet への公開と接続先名は Kubernetes 側で設定する。

2つの image を build して参照名を `CLI_IMAGE_REF` と `SSH_IMAGE_REF` に設定すると、公開鍵認証、fish 設定、SSH 入出力、切断後の復帰を検証できる。

```bash
bash tests/workspace-ssh-smoke.sh "$CLI_IMAGE_REF" "$SSH_IMAGE_REF"
```

# コンテナのイメージのビルド方法

local で確認する時は、日常利用中の `latest` を上書きしないように別 tag を使う。

```bash
docker build --progress=plain -t cli-tool-docker:local-test .
docker run --rm --entrypoint bash cli-tool-docker:local-test -lc 'cat /etc/os-release; cha --version || true; navi --version; zoxide --version; yq --version; tenv version; command -v terraform; command -v tofu; command -v terragrunt; command -v atmos; command -v uv; command -v uvx; test "$(command -v uvx)" = /usr/local/bin/uvx; /usr/local/bin/uvx --version; command -v fff-mcp; devrag --version; command -v leaf; gcloud --version; pipx --version; dig -v; 7z | sed -n "2p"'
```

nerdctl で build する場合:

```bash
nerdctl build -t cli-tool-docker:local-test .
```

Codex を devcontainer 内から使う場合、`/var/run/docker.sock` や `/run/containerd/containerd.sock` の権限が足りないことがある。
その場合は `sudo docker ...` に進まず、ホスト側の shell で上記を実行する。

# Ubuntu 26.04 / image size メモ

Ubuntu 26.04 移行時の package rename、Chawan 追加、smoke test、image size、layer 削減の詳細は Hugo 側へ移した。

- `/home/kaoru/ghq/github.com/tin-machine/hugo/content/docker/docker-ubuntu-26-04-cli-tool-docker/`
- `/home/kaoru/ghq/github.com/tin-machine/hugo/content/docker/docker-image-size-cli-tool-docker/`

# 設定の背景

## repo-local skills

この repository には、CLI tool 追加作業用の Codex skill を `skills/add-cli-tool/` に置いている。

新しい tool を追加する時は、`Dockerfile` へ直接書き足す前にこの skill を使い、導入経路を分類する。

- `apt`: Ubuntu 26.04 package で十分な tool
- `aqua.yaml`: aqua registry にあり、version pin と checksum 管理をしたい standalone CLI
- `Dockerfile` の prebuilt download: upstream release asset や `.deb` を arch 分岐込みで扱う tool
- source build stage: apt / aqua / prebuilt では必要機能を満たせない tool
- Volta/npm、cargo、gem、luarocks: language ecosystem に自然に属する tool

想定 prompt:

```text
Use $add-cli-tool to add <tool-name> to cli-tool-docker.
```

この skill は Gemma 4 12B 級のローカル LLM でも迷いにくいように、読むファイル、`rg` の順序、導入経路の優先順位、編集対象、出力形式を固定している。

## Renovate / aqua

Renovate は `renovate.json` で GitHub Actions の digest pin と aqua package 更新を扱う。
release timestamp が取れる version update は `minimumReleaseAge: 14 days` の対象なので、新しい release が出ても 14 日経ってから PR が来る。
GitHub Actions の初回 pin や digest 更新は、Renovate の update type 上 `minimumReleaseAge` の対象外になる場合がある。
Renovate は `.github/workflows/renovate.yml` の scheduled workflow で self-hosted 実行し、対象 repository は `.github/renovate-global.json` の `repositories` で明示する。

`aqua.yaml` は checksum 必須にしている。
aqua 管理 package を追加・更新した時は、次で `aqua-checksums.json` も更新する。

```bash
aqua update-checksum -prune
```

aquaproj の Renovate preset は `aqua.yaml` の version 更新を検出するが、`aqua-checksums.json` の再生成までは行わない。
この repository では Renovate の `postUpgradeTasks` で `.github/scripts/update-aqua-checksum.bash` を実行し、Renovate PR では checksum も同じ branch に更新する。
手元で `aqua.yaml` を変更した場合は、commit 前に `aqua update-checksum -prune` を実行して `aqua-checksums.json` を揃える。

`uv` / `uvx` は `aqua.yaml` で管理するが、Codex や MCP client のように shell を介さず
`execve(2)` で起動する用途では aqua proxy が解決に失敗することがある。このため
Dockerfile では `aqua install` 後に `aqua which uv` / `aqua which uvx` の実体へ向けた
symlink を `/usr/local/bin` に置き、`/usr/local/bin` を `/usr/local/aqua/bin` より先にしている。

## Terraform / OpenTofu / Terragrunt

Terraform 系のバージョン管理は `aqua.yaml` の `tofuutils/tenv` で行う。
`aqua install` により `tenv` だけでなく、`terraform`、`tf`、`tofu`、`terragrunt`、`atmos` も PATH 上の proxy として使える。

実際の Terraform / OpenTofu / Terragrunt / Atmos の各バージョンは、`tenv` が既定で `$HOME/.tenv` 配下に入れる。
`shell.bash` では host の `$HOME` を bind mount しているため、image rebuild 後も tenv 管理の実体は host home 側に残る。

この image には個別の `terraform` binary を直接焼かず、project ごとの version file と `tenv` に寄せる。
その方が Terraform と OpenTofu の切り替え、Terragrunt 併用、image size、更新タイミングを分離しやすい。

## DevRag

DevRag は Codex / OpenCode から local document RAG を使うための MCP server として、GitHub Releases の Linux binary を checksum 固定で導入する。

Linux binary は ONNX Runtime を同梱しないため、image 内には Microsoft 公式 ONNX Runtime CPU tarball も配置する。`/usr/local/bin/devrag` は wrapper で、`LD_LIBRARY_PATH` と `DEVRAG_THREADS=8` を設定してから `/opt/devrag/<version>/devrag-<arch>` を起動する。

Codex の `~/.codex/config.toml` や DevRag の `~/.config/devrag/homecluster-docs.json`、vector DB、embedding model は host `$HOME` の bind mount 側を使う想定である。image に入れるのは DevRag executable と ONNX Runtime までに留める。

## manpage

現在の Dockerfile では `unminimize` は実行していない。
ただし `man-db` を引く package や各 package の付属ドキュメントは通常の apt install 経由で入るため、日常 CLI image としては size が大きくなりやすい。

## neovim

#### コンパイルしている理由

Dockerfile では Ubuntu package の `neovim` ではなく、upstream の `release-0.11` branch を `/opt/neovim` へ install している。
これは rafi config 側の Neovim plugin 群や Copilot 用に、Ubuntu package の更新タイミングへ依存しないため。

将来 Ubuntu 側の `neovim` package で必要な version と機能が満たせるようになったら、source build をやめる余地がある。

#### neovimのビルドオプション
[ここに説明がある](https://github.com/neovim/neovim/wiki/Building-Neovim#building)
- Release
- Debug
- RelWithDebInfo

# ログインするユーザーの作成をどうするか?

これを行わないとコンテナに入った後、ファイルのuid:gidが実環境と異なってしまう。
ただ汎用的に使えるコンテナイメージにしたいのでユーザ名、uid、gidはDockerfileには含めたくない。

現在は `entrypoint.bash` と `shell.bash` で役割を分けている。

- `shell.bash` はコンテナを `--user 0:0` で起動し、ホストの `HOME`、Docker socket、containerd socket などをマウントし、`UID`、`GID`、`USER`、`HOME` を環境変数で渡す。
- `entrypoint.bash` は起動時にホストと同じ UID/GID のユーザーを作成する。既に同じ UID が存在する場合は `useradd -o` を使い、Ubuntu イメージ由来の既存ユーザーと衝突しても作業ユーザー名で入れるようにする。
- `entrypoint.bash` は作業ユーザーから `sudo`/`admin` 補助グループを外し、必要な場合に `dialout` と Docker socket 用 group を付与する。`dialout` はシリアルポートアクセスを想定したもの。
- 実際にシェルへ入る時は、`docker exec --user uid:gid` を直接使わず、root で `exec` してからコンテナ内の `setpriv --init-groups` で作業ユーザーへ降りる。これにより `/etc/group` に基づく supplementary groups が反映される。

`entrypoint.bash` の最後では `gosu "${USER_NAME}" "$@"` を使う。
このため default の `tail -F /dev/null` も作成済みユーザーで実行される。
ただし、後続の対話シェルでは `shell.bash` 側の `setpriv --init-groups` が重要になる。

`shell.bash` で起動する常駐コンテナには Docker / nerdctl とも `--init` を付ける。
PID 1 や `<defunct>` の調査メモは Hugo 側の Ubuntu 26.04 移行メモに置く。

以前は `su - ユーザー名 -c fish` のような入り方も試したが、TTY 周りで下記のようなエラーが出ることがあった。

```
warning: No TTY for interactive shell (tcgetpgrp failed)
setpgid: デバイスに対する不適切なioctlです
```

このため、現在は `su` に依存せず `gosu` と `setpriv` を使う構成にしている。

# コンテナ内から Docker を使う

この image では、コンテナ内で別の Docker daemon を起動する Docker-in-Docker ではなく、ホストの `/var/run/docker.sock` を bind mount してホストの Docker daemon を操作する。
いわゆる Docker-outside-of-Docker の形になる。

socket は通常 `0660 root:<docker group gid>` なので、コンテナ内の作業ユーザーがその数値 GID を supplementary group として持つ必要がある。
重要なのは image 内の `docker` group の GID ではなく、ホスト上の `/var/run/docker.sock` の GID である。

`shell.bash` は起動時にホストの socket GID を取得し、`DOCKER_SOCK_GID` として渡す。
`entrypoint.bash` はその GID の group をコンテナ内に作成し、作業ユーザーへ追加する。
これにより、後続の対話 shell で `setpriv --init-groups` を使っても Docker socket 用 group が残る。

確認コマンド:

```bash
stat -Lc '%n %a %u %g %U %G %F' /var/run/docker.sock
id -a
docker version
docker ps
```

# コンテナ内から GPU render node を使う

`/dev/dri/renderD128` がある host では、`shell.bash` がその数値 GID を
`DRI_RENDER_GID` として渡す。`entrypoint.bash` は対応する group をコンテナ内に
作成して作業ユーザーへ追加するため、`setpriv --init-groups` 後も render node へ
アクセスできる。コンテナは `--privileged` で起動するため、追加の `--device` 指定は不要である。

host とコンテナ内で次を確認する。

```bash
stat -Lc '%n %a %u %g %U %G %F' /dev/dri/renderD128
id -a
test -rw /dev/dri/renderD128 && echo 'render node accessible'
```

`renderD128` がない host では GPU 用の group は追加されない。この変更は WebGPU/Vulkan
利用の前提となる Unix 権限を整えるだけで、利用するアプリケーションの GPU backend を有効化するものではない。

`shell.bash` は `docker run --rm` で常駐コンテナを起動する。
このため `cli-tool-docker` コンテナが停止するとコンテナオブジェクトは自動削除され、次回は新しいコンテナを作成する。
host の `$HOME` は bind mount なので、作業ファイルはコンテナ削除の対象外。

既に古い設定で実行中の `cli-tool-docker` コンテナには、entrypoint の group 追加や `--init` などの起動設定変更は反映されない。
また `entrypoint.bash` は image に焼かれるため、この修正を使うには image rebuild か、更新済み image の pull が必要になる。
ローカルで確認する場合は、`CLI_TOOL_DOCKER_IMAGE` で使う image repository を差し替えられる。

```bash
docker build --progress=plain -t cli-tool-docker:latest .
docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | grep cli-tool-docker
docker stop <container-id>
CLI_TOOL_DOCKER_IMAGE=cli-tool-docker ./shell.bash
```

旧設定で停止済みの同名コンテナが残っている場合、`docker ps` では見えないが、`docker run --name cli-tool-docker` は名前衝突で失敗する。
確認する場合は `docker ps -a --filter name=cli-tool-docker` を使う。
現在の `shell.bash` は停止済みの `cli-tool-docker` が残っていれば、再利用せず削除してから新規作成する。

```bash
docker ps -a --filter name=cli-tool-docker
./shell.bash
```

`/run/containerd/containerd.sock` は環境によって `0660 root:root` になっている。
この場合、非 root の作業ユーザーから `nerdctl` でホスト containerd を直接操作するには、ホスト側で socket group を設計し直す必要がある。
日常用途では、まず Docker socket 経由の `docker`/`docker compose` を使う方が単純。

Docker credential helper など、host 側設定に依存するトラブルシュートは Hugo 側の Ubuntu 26.04 移行メモに置く。
