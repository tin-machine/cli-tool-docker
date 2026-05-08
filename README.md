# cli-tool-docker

通常、macなりLinuxでCLIの作業環境を作成すると環境を壊すリスクが恐ろしい。
コンテナイメージの形で利用すると、カジュアルにアップデートなり、新しいツールの検証ができる。
このため自分が良く使うコマンドを集めたコンテナイメージを作る事にした。

# コンテナのイメージのビルド方法

```
nerdctl build -t cli-tool-docker:latest ~/workspace/git/github.com/tin-machine/cli-tool-docker/
```

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
