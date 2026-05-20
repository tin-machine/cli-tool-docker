# cli-tool-docker

通常、macなりLinuxでCLIの作業環境を作成すると環境を壊すリスクが恐ろしい。
コンテナイメージの形で利用すると、カジュアルにアップデートなり、新しいツールの検証ができる。
このため自分が良く使うコマンドを集めたコンテナイメージを作る事にした。

# コンテナのイメージのビルド方法

```
nerdctl build -t cli-tool-docker:latest ~/workspace/git/github.com/tin-machine/cli-tool-docker/
```

Ubuntu 26.04 向けのローカル検証では、Docker を使えるホスト上で次のように別タグを付けてビルドすると日常利用中の `latest` を上書きせずに確認できる。

```
docker build -t cli-tool-docker:ubuntu-26.04-test .
docker run --rm --entrypoint bash cli-tool-docker:ubuntu-26.04-test -lc 'cat /etc/os-release; cha --version || true; navi --version; zoxide --version; dig -v; 7z | sed -n "2p"'
```

Codex を devcontainer 内から使う場合、`/var/run/docker.sock` や `/run/containerd/containerd.sock` の権限が足りないことがある。その場合は `sudo docker ...` に進まず、ホスト側の shell で上記を実行する。

# Ubuntu 26.04 メモ

- ベースイメージは `ubuntu:26.04`。
- 26.04 では旧名の `dnsutils`、`dotnet-sdk-8.0`、`p7zip-full`、`p7zip-rar`、`mono-utils`、`ncurses-dev` はそのままでは package index に存在しない。Dockerfile では `bind9-dnsutils`、`7zip`、`7zip-rar`、`libncurses-dev` に寄せている。
- `dotnet-sdk` と `mono-devel` はイメージサイズへの影響が大きいため、日常用 CLI コンテナからは外している。`ilspycmd` や `monodis` 相当が必要な場合は、別 image/profile として足す方がよい。
- `7zip` パッケージは `/usr/bin/7z`、`/usr/bin/7za`、`/usr/bin/7zr`、`/usr/bin/p7zip` を入れる。`7zz` はこの package には含まれない。
- `aqua.yaml` の `kayac/ecspresso` は version 未指定だと aqua が無視するため、`v2.8.4` で pin している。
- テキストブラウザは従来の `w3m-img` に加えて Chawan を入れる。Chawan 0.4.0 の公式 `.deb` は amd64 のみなので、現時点では `linux/amd64` build だけに入る。`linux/arm64` は公式 arm64 binary が出るか source build を検証してから追加する。
- Julia は日常用 CLI コンテナ内での利用根拠が見つからず、サイズ影響も大きいため外している。
- Rust でビルドする `navi` / `zoxide` は、最終イメージへ `/opt/cargo` や `/opt/rustup` を丸ごとコピーせず、builder stage から実行ファイルだけを `/usr/local/bin` にコピーしている。
- Volta は Node.js と npm global CLI の管理に使っている。この image では `node@24.2.0`、`claude`、`gemini`、`codex`、`clawdbot`、`jsonlint`、`markdownlint` を入れている。
- Volta 経由の npm global install 後は `/root/.npm` と `/root/.cache/node-gyp` を同じ `RUN` 内で削除し、npm cache を最終 layer に残さない。
- `/usr/local/aqua/pkgs` は aqua 管理 CLI の実体置き場なので、削除すると初回実行時に再ダウンロードが必要になる。常時ネットワーク前提なら削れるが、オフライン利用や起動直後の確実性を優先して残している。

# イメージサイズメモ

Ubuntu 26.04 のローカル検証では、`dotnet-sdk` / `mono-devel` / Julia の削除、Volta の npm cache 削除、Rust builder からの binary-only copy により、Docker 29 の表示で次のように減った。

- content size: `4.58GB` -> `2.92GB`
- local disk usage: `18.1GB` -> `11.9GB`

# 設定の背景

## manpageが使いたかったので unminimize した、
イメージのサイズは結構ふえる。

## neovim

#### コンパイルしている理由
rafi-config が使用する razy.vim が neovim 8以上である必要がある。

copilotも利用している( [github/copilot.vim: Neovim plugin for GitHub Copilot](https://github.com/github/copilot.vim) ) によるとNeovimであれば良いらしい。
Ubuntuの標準のneovimのバージョンが8になったら素のneovimでも大丈夫か試す。
(一方、Vimにはバージョンの縛りがある)

#### neovimのビルドオプション
[ここに説明がある](https://github.com/neovim/neovim/wiki/Building-Neovim#building)
- Release
- Debug
- RelWithDebInfo

# ログインするユーザーの作成をどうするか?

これを行わないとコンテナに入った後、ファイルのuid:gidが実環境と異なってしまう。
ただ汎用的に使えるコンテナイメージにしたいのでユーザ名、uid、gidはDockerfileには含めたくない。

現在は `entrypoint.bash` と `shell.bash` で役割を分けている。

- `shell.bash` はコンテナを root で常駐起動する。ホストの `HOME`、Docker socket、containerd socket などをマウントし、`UID`、`GID`、`USER`、`HOME` を環境変数で渡す。
- `entrypoint.bash` は起動時にホストと同じ UID/GID のユーザーを作成する。既に同じ UID が存在する場合は `useradd -o` を使い、Ubuntu イメージ由来の既存ユーザーと衝突しても作業ユーザー名で入れるようにする。
- `entrypoint.bash` は作業ユーザーから `sudo`/`admin` 補助グループを外し、必要な場合に `dialout` を付与する。これはシリアルポートアクセスを想定したもの。
- 実際にシェルへ入る時は、`docker exec --user uid:gid` を直接使わず、root で `exec` してからコンテナ内の `setpriv --init-groups` で作業ユーザーへ降りる。これにより `/etc/group` に基づく supplementary groups が反映される。

`entrypoint.bash` の最後では `gosu "${USER_NAME}" "$@"` を使って、常駐プロセス自体も作成済みユーザーで実行する。
ただし、後続の対話シェルでは `shell.bash` 側の `setpriv --init-groups` が重要になる。

以前は `su - ユーザー名 -c fish` のような入り方も試したが、TTY 周りで下記のようなエラーが出ることがあった。

```
warning: No TTY for interactive shell (tcgetpgrp failed)
setpgid: デバイスに対する不適切なioctlです
```

このため、現在は `su` に依存せず `gosu` と `setpriv` を使う構成にしている。

# docker in docker だと osxkeychain が見つからないエラーが出る

docker compose up をした際に次のエラーが出る

```
error getting credentials - err: exec: "docker-credential-osxkeychain": executable file not found in $PATH, out:
```

~/.docker/config.json に "credsStore": "osxkeychain" が記載されているので出る。
mac環境では `brew install docker-credential-helpers` でインストールできるが docker in docker 内では見つからないしバイナリも提供されていない。
他の選択肢としては下記がある
- docker-credential-pass（Linux ではこれが一般的）
- docker-credential-secretservice（GNOME Keyring を利用）
~/.docker/config.json を修正：

```
{
  "credsStore": "pass"
}
```

## 認証情報の保存場所

Docker はログイン時 (docker login …) に入力した認証情報を、
docker-credential-pass というヘルパープログラムを通じて保存します。
このヘルパーは Linux の pass (Password Store) を利用して、GPG で暗号化された状態で保存します。
つまり平文ではなく、~/.password-store/ に GPG 鍵で暗号化されて記録される
docker-credential-pass が呼ばれて取得・削除・一覧を行う
