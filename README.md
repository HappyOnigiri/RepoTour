# Repo Tour

**「このリポジトリ、何してるの？」を HTML レポートひとつで答えるプラグインです。**

AI エージェントがコードベースを読み解き、プロダクト概要・技術スタック・設計・機能一覧をまとめた静的レポートを生成します。オンボーディングやコードレビューの起点としてお使いください。

<p align="center">
  <img src=".github/resources/repo-tour.webp" alt="Repo Tour" width="600" />
</p>

## インストール

### Claude Code

```bash
/plugin marketplace add HappyOnigiri/RepoTour
/plugin install repo-tour@repo-tour
```

### Cursor

このリポジトリを clone してプロジェクトとして開くと、`.cursor-plugin/plugin.json` が自動検出されます。

自動検出されない場合は **Cursor Settings → Plugins** から `https://github.com/HappyOnigiri/RepoTour` を追加してください。

### VS Code + GitHub Copilot

プラグイン対応バージョンの Copilot 拡張機能がインストールされた VS Code でこのリポジトリを clone して開くと、`.copilot-plugin/plugin.json` が自動検出されます。

### その他のプラットフォーム (Codex, Gemini CLI, OpenCode, Vibe, Cline, Kiro など)

```bash
curl -fsSL https://raw.githubusercontent.com/HappyOnigiri/RepoTour/main/install.sh | bash
```

プラットフォームを指定する場合:

```bash
curl -fsSL https://raw.githubusercontent.com/HappyOnigiri/RepoTour/main/install.sh | bash -s codex
```

`install.sh --help` で対応プラットフォーム一覧を確認できます。

## 使い方

```
/repo-tour:repo-tour
```

これだけです。エージェントがリポジトリを調査し、`docs/repo-tour/` に HTML レポートを出力します。

## 生成されるレポート

| ページ | 内容 |
|---|---|
| トップ | リポジトリ全体の概要 |
| プロダクト概要 | 想定読者、主要概念、最初に読む場所 |
| 技術スタック | 使用技術とその用途 |
| 設計 | アーキテクチャ方針、配置ルール |
| 機能詳細 | 機能ごとの個別ページ |

各ファイルには GitHub・Cursor・VS Code へのリンクが付き、ソースコードへすぐ飛べます。

## 必要なもの

- Ruby (ERB テンプレートの処理に使います)

## ライセンス

[MIT](LICENSE)
