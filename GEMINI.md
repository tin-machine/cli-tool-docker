# GEMINI.md

## プロジェクト概要

このリポジトリは、開発作業で頻繁に使用するCLIツールをまとめたDockerコンテナイメージを構築・管理するためのものです。

主な目的は、ローカル環境を汚すことなく、様々なツールを最新の状態で、かつ安定して利用できる環境を提供することです。コンテナ化により、環境の再現性やポータビリティを高めています。

## 主要な技術スタック

- **コンテナ:** Docker / nerdctl
- **ベースイメージ:** Ubuntu 25.04
- **パッケージ管理:**
    - `apt`: OS基本パッケージ
    - `aqua`: CLIツールのバージョン管理
    - `npm`: Node.js関連パッケージ
    - `cargo`: Rust関連パッケージ
- **CI/CD:** GitHub Actions
- **依存関係更新:** Renovate

## 主な機能・特徴

- **豊富なCLIツール:**
    - `neovim`, `tmux` (ソースからビルド)
    - `lazygit`, `ghq`, `yazi`
    - `kubectl`, `helm`, `terraform-switcher`
    - `aws-cli`, `gcloud`
    - `docker`, `nerdctl`
    - その他、`bat`, `fzf`, `ripgrep` など多数の便利ツール
- **マルチアーキテクチャ対応:**
    - `linux/amd64` と `linux/arm64` の両方をサポートしています。
- **動的なユーザー作成:**
    - `entrypoint.sh` スクリプトにより、コンテナ起動時にホストマシンのユーザー情報（UID/GID）を引き継いだユーザーを動的に作成します。これにより、ファイルパーミッションの問題を回避します。
- **自動化されたビルドとデプロイ:**
    - GitHub Actions を利用して、`main` ブランチへのプッシュ時にコンテナイメージをビルドし、GitHub Container Registry (ghcr.io) へ自動的にプッシュします。
- **依存関係の自動更新:**
    - Renovate を導入しており、`Dockerfile` や `aqua.yaml` などで定義されたツールのバージョンを定期的にチェックし、更新プルリクエストを自動で作成します。

## 使い方

`shell.bash` スクリプトを実行することで、ローカルにコンテナイメージが存在しない場合はビルドまたはプルし、実行中のコンテナがなければ起動します。その後、コンテナ内に入って作業を開始できます。

```bash
./shell.bash
```

このスクリプトは、`docker` または `nerdctl` を自動で検知して使用します。
