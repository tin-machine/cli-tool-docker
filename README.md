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
release timestamp が取れる version update は `minimumReleaseAge: 7 days` の対象なので、新しい release が出ても 7 日経ってから PR が来る。
GitHub Actions の初回 pin や digest 更新は、Renovate の update type 上 `minimumReleaseAge` の対象外になる場合がある。

`aqua.yaml` は checksum 必須にしている。
aqua 管理 package を追加・更新した時は、次で `aqua-checksums.json` も更新する。

```bash
aqua update-checksum -prune
```

aquaproj の Renovate preset は `aqua.yaml` の version 更新を検出するが、`aqua-checksums.json` の再生成までは行わない。
Renovate が aqua package 更新 PR を作った場合は、checksum 更新を手元で足すか、別途 CI 化する必要がある。

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
