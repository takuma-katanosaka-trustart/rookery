# Rookery 🐧

> Apple の [`container`](https://github.com/apple/container) を基盤に、macOS 上の Linux コンテナを **Docker なしで** 管理・実行する macOS ネイティブの GUI アプリケーション。OSS（Swift / SwiftUI）。

> [!NOTE]
> 現在 **設計・初期開発フェーズ（Phase 0）** です。動作するアプリはまだありません。設計と開発基盤を整備中です。

---

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

## 目次

- [Rookery とは](#rookery-%E3%81%A8%E3%81%AF)
- [動作要件](#%E5%8B%95%E4%BD%9C%E8%A6%81%E4%BB%B6)
- [ドキュメント](#%E3%83%89%E3%82%AD%E3%83%A5%E3%83%A1%E3%83%B3%E3%83%88)
- [開発環境の準備](#%E9%96%8B%E7%99%BA%E7%92%B0%E5%A2%83%E3%81%AE%E6%BA%96%E5%82%99)
  - [前提](#%E5%89%8D%E6%8F%90)
  - [セットアップ](#%E3%82%BB%E3%83%83%E3%83%88%E3%82%A2%E3%83%83%E3%83%97)
  - [Apple Developer ライセンスについて](#apple-developer-%E3%83%A9%E3%82%A4%E3%82%BB%E3%83%B3%E3%82%B9%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)
- [品質・コントリビュート](#%E5%93%81%E8%B3%AA%E3%83%BB%E3%82%B3%E3%83%B3%E3%83%88%E3%83%AA%E3%83%93%E3%83%A5%E3%83%BC%E3%83%88)
- [ライセンス](#%E3%83%A9%E3%82%A4%E3%82%BB%E3%83%B3%E3%82%B9)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Rookery とは

`apple/container` は、各コンテナを軽量 Linux VM として動かす CLI ツールです。Rookery はその上に乗る GUI で、コンテナ／イメージ管理に加え、**開発者ワークフローの統合**を軸に差別化します。

- **Stacks（Compose 風の宣言的マルチコンテナ）** — `apple/container` 単体にはない、複数コンテナをまとめて起動・破棄する体験
- **ゼロコンフィグなオンボーディング** — `container` の導入・`system start`・kernel 設定を GUI が検知・支援
- **日本語ファースト + i18n**

名前の由来は **rookery（ペンギンの集団繁殖地）**。Linux（＝ペンギン）コンテナが多数集う「ホスト」の比喩です。先行する Swift 製 GUI [Orchard](https://github.com/andrew-waters/orchard) への敬意も込めています。

## 動作要件

- **macOS 26 以降 / Apple silicon**（`apple/container` の制約に準拠）
- [`apple/container`](https://github.com/apple/container) 1.0.0 以上がインストール済みで、`container system start` 済みであること

## ドキュメント

| ドキュメント                       | 内容                                                                         |
| ---------------------------------- | ---------------------------------------------------------------------------- |
| [docs/DESIGN.md](docs/DESIGN.md)   | 設計の全体像（アーキテクチャ・連携方式・画面・ロードマップ・構成図）         |
| [docs/PRIMER.md](docs/PRIMER.md)   | 技術プライマー（Swift / 並行性 / XPC / 仮想化スタックを運用視点で学ぶ）      |
| [docs/TOOLING.md](docs/TOOLING.md) | 開発ツールチェーン（mise / SPM / lint / テスト / CI / サプライチェーン対策） |

> 構成図（アーキテクチャ・レイヤ・画面）は DESIGN.md 内に SVG で埋め込まれています。

## 開発環境の準備

Apple Developer Program（有料）は **不要**です（[後述](#apple-developer-ライセンスについて)）。

### 前提

- [`apple/container`](https://github.com/apple/container) を導入し、`container system start` を実行しておく
- [mise](https://mise.jdx.dev/) を導入しておく（Swift / Node / pnpm を一括管理。詳細は [TOOLING §1](docs/TOOLING.md)）

### セットアップ

```sh
# リポジトリを取得
git clone https://github.com/takuma-katanosaka-trustart/rookery.git
cd rookery

# 1) ツールチェーン（Swift / Node / pnpm を mise.toml のバージョンで一括導入）
mise install

# 2) テキスト品質ツール + Git フック（cspell / secretlint / textlint / lefthook）
pnpm install

# 3) ビルド & テスト（SPM パッケージ整備後に有効）
swift build
swift test
```

開発ツールの詳細・設定・CI 構成は [docs/TOOLING.md](docs/TOOLING.md) を参照してください。

### Apple Developer ライセンスについて

**ローカルでの開発・ビルド・実行・テストに、有料の Apple Developer Program（年 99 USD）は不要です。**

| 用途                                                     | 有料プログラム |
| -------------------------------------------------------- | -------------- |
| ローカルでビルド・実行・デバッグ・テスト                 | 不要           |
| OSS としてソース公開・コントリビュート                   | 不要           |
| 署名（Developer ID）＋ notarization した配布物の一般配布 | 必要           |
| Mac App Store 配布                                       | 必要           |

有料プログラムが要るのは「**署名して一般に配布する**」最終段階だけです。それまでは未署名ビルドをローカルで動かして開発できます。本アプリは VM を直接動かさず `container-apiserver` に XPC/CLI で接続する設計のため、特殊な entitlement も基本不要です（[DESIGN §5](docs/DESIGN.md)）。

## 品質・コントリビュート

コミット時に [lefthook](lefthook.yml) が変更ファイルへ cspell（英語スペル）・secretlint（機密検出）・textlint（日本語 prose）を実行し、CI（[.github/workflows/quality.yml](.github/workflows/quality.yml)）で全文走査します。詳細は [docs/TOOLING.md](docs/TOOLING.md)。

ロードマップ（Phase 0〜3）は [DESIGN.md のロードマップ](docs/DESIGN.md)を参照してください。

## ライセンス

[Apache License 2.0](LICENSE)。`apple/container` との整合を意図しています。
