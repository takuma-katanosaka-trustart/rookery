# ツールチェーン / 開発環境セットアップ

> 対象: Swift 開発が初めての人でも、このドキュメントの上から順に実行すれば開発環境が整うことを目指す。
> 方針: **標準・最小**。バージョンを固定できるものは固定し、「手元と CI で結果が違う」を防ぐ。
> 関連: 各ツールの「なぜ必要か」は [PRIMER.md](./PRIMER.md)、設計上の位置づけは [DESIGN.md 付録A](./DESIGN.md) を参照。

---

## 0. 推奨ツール一覧（早見表）

| カテゴリ | ツール | 役割 | 必須度 |
| --- | --- | --- | --- |
| パッケージ管理 | **Swift Package Manager (SPM)** | 依存・モジュール管理 | 必須（標準同梱） |
| ツールチェーン管理 | **mise** | Swift 本体 + 補助ツールのバージョン固定・切替 | 強く推奨 |
| フォーマッター | **swift-format** | コード整形（公式） | 推奨 |
| Linter | **SwiftLint** | 危険なコードパターン検出 | 推奨 |
| 型・並行性 | **Swift 6 strict concurrency** | データ競合をコンパイル時に排除 | 必須（設定で有効化） |
| テスト | **Swift Testing** + XCUITest | 単体/統合テスト・UIテスト | 推奨 |
| 依存脆弱性 | **Dependabot** + **CodeQL** | 既知脆弱性・基本的なSAST | 任意（CIで） |
| 英語スペル | **cspell** | ドキュメント/コメントの英語誤字検出 | 推奨 |
| シークレット検出 | **secretlint** | 資格情報の誤コミット防止 | 強く推奨 |
| 日本語 prose | **textlint** | 日本語ドキュメントの表記ゆれ・冗長表現 | 推奨 |
| Git フック | **lefthook** | コミット前チェックの一元実行 | 推奨 |
| CI/CD | **GitHub Actions** | ビルド/lint/test/署名/notarize | 推奨 |

> 入れないもの: CocoaPods / Carthage（SPM で代替）、Fastlane（配布が複雑化するまで不要）、重量級 SAST。
> JS 製ツール（cspell / secretlint / textlint / lefthook）の Node・pnpm も **mise で一元管理**する（§1, §9）。

---

## 1. ツールチェーン管理：mise

[mise](https://mise.jdx.dev/)（旧 rtx）は多言語対応のバージョン管理ツール。Swift 本体に加え、**SwiftLint や swift-format などの補助ツールも 1 ファイル（`mise.toml`）で固定**できるのが採用理由。「手元と CI で linter のバージョンが違って結果が割れる」事故を防げる。

> **Apple 公式の代替**: [swiftly](https://www.swift.org/blog/introducing-swiftly_10/)（Swift 公式のツールチェーン管理）でも Swift 本体の管理は可能。ただし swiftly が管理するのは Swift 本体のみで、補助ツールは別管理になる。本プロジェクトはツールを集約できる mise を primary とする。

### インストール

```sh
curl https://mise.run | sh
# シェル設定に hook を追加（zsh の例。実行後に新しいシェルを開く）
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
mise --version
```

### バージョン固定（リポジトリルート `mise.toml` をコミット）

ディレクトリに入ると、ここで指定したバージョンが自動で有効になる。

```toml
[tools]
swift = "6.1"
swiftlint = "latest"
# swift-format は Swift 同梱のため mise では管理しない（§3 参照）

# ドキュメント/テキスト品質ツール（cspell / secretlint / textlint）用ランタイム（§9）
node = "22"
pnpm = "latest"
```

```sh
mise install        # mise.toml の全ツールを導入
mise exec -- swift --version
```

> ⚠️ **重要な棲み分け（mise / swiftly 共通の制約）**: mise が管理するのは **swift.org のオープンソース・スタンドアロンツールチェーン**で、効くのは `swift build` / `swift test` / `swift format`（CLI・CI）の範囲。
> 一方、**SwiftUI プレビュー・UI テスト・コード署名/notarization は Xcode 同梱のツールチェーンを使う**（[DESIGN §5](./DESIGN.md)）。
> したがって「**CLI / CI は mise、UI と配布は Xcode**」と役割を分けるのが鉄則。mise は Xcode の Swift を置き換えない。

---

## 2. パッケージ管理：Swift Package Manager (SPM)

追加インストール不要（Swift に同梱）。本プロジェクトはマルチモジュール構成（[DESIGN §3](./DESIGN.md)）を SPM で表現する。

### よく使うコマンド

```sh
swift build            # ビルド
swift test             # テスト実行
swift package resolve  # 依存解決
swift package update   # 依存更新
swift run              # 実行（CLI ターゲットの場合）
```

### `Package.swift` 雛形（マルチモジュールの骨子）

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Wharf",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Backend", targets: ["Backend"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        // 端末エミュレータ（exec 用, 採用は PoC 後に確定 / DESIGN §5）
        // .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Domain", dependencies: ["Core"]),
        .target(name: "Backend", dependencies: ["Domain", "Core"]),
        .testTarget(name: "BackendTests", dependencies: ["Backend"]),
    ],
    // 全ターゲットで Swift 6 の厳格並行性を有効化（§4）
    swiftLanguageModes: [.v6]
)
```

> 依存方向は `App → Features → Domain → Backend → Core`（[DESIGN §3](./DESIGN.md)）。`Package.swift` の `dependencies` でこの方向を守る。

---

## 3. フォーマッター：swift-format（公式）

Swift ツールチェーンに同梱。コードの見た目を統一する。

### 実行

```sh
swift format --in-place --recursive Sources/ Tests/   # 整形を適用
swift format lint --recursive Sources/                 # 整形違反のチェックのみ（CI 用）
```

### 設定ファイル雛形（リポジトリルート `.swift-format`）

```json
{
  "version": 1,
  "indentation": { "spaces": 4 },
  "lineLength": 100,
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "rules": {
    "AlwaysUseLowerCamelCase": true,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": true
  }
}
```

---

## 4. Linter：SwiftLint

危険なコードパターン（強制アンラップの濫用、巨大関数、未使用コードなど）を検出する。[PRIMER §12 チェックリスト](./PRIMER.md) の事故ポイントを機械的に拾う。

### インストール

`mise.toml` に記載済みなら `mise install` で導入される（§1）。個別に入れる場合:

```sh
mise use swiftlint@latest   # mise.toml に追記して導入
# もしくは: brew install swiftlint
```

### 設定ファイル雛形（リポジトリルート `.swiftlint.yml`）

```yaml
# 本プロジェクトの方針: 事故に直結するルールを重視
opt_in_rules:
  - force_unwrapping        # ! の強制アンラップを警告（クラッシュ源）
  - empty_count
  - first_where
  - explicit_init
  - closure_spacing

disabled_rules:
  - todo                    # TODO コメントは許容

included:
  - Packages
  - App

excluded:
  - .build
  - "**/.build"

line_length:
  warning: 120
  error: 200

type_body_length:
  warning: 300

function_body_length:
  warning: 60
```

### 実行

```sh
swiftlint              # 警告/エラーを表示
swiftlint --fix        # 自動修正可能なものを修正
```

---

## 5. 型・並行性チェック：Swift 6 strict concurrency

**追加ツール不要**。Swift コンパイラ自身が最強の静的解析。`Package.swift` で `swiftLanguageModes: [.v6]` を指定すると、`Sendable` 違反やデータ競合が**コンパイルエラー**になる（[PRIMER §2](./PRIMER.md)）。

- 既存コードを段階移行する場合は、ターゲット単位で `.enableUpcomingFeature("StrictConcurrency")` を使う手もある。
- 本プロジェクトは新規なので、**最初から `.v6` で開始**するのが最も低コスト（後付けは苦痛）。

---

## 6. テスト：Swift Testing + XCUITest

### Swift Testing（単体・統合テスト, 新公式）

```swift
import Testing
@testable import Backend

@Test("CLI 出力の JSON を Container にマッピングできる")
func parsesContainerList() async throws {
    let backend = MockBackend(containers: [.sample])   // DESIGN §2.2 のモック
    let result = try await backend.listContainers()
    #expect(result.count == 1)
    #expect(result.first?.name == "web")
}
```

```sh
swift test                       # 全テスト
swift test --filter BackendTests # 絞り込み
```

### UI テスト

UI（SwiftUI 画面）の自動テストは従来の **XCUITest**（Xcode 上）を使う。優先度は低く、Phase 1 後半以降で導入。

---

## 7. 依存の脆弱性監視（CI で、任意）

Swift には成熟した SAST は少ない。現実的な最小構成：

### Dependabot（[.github/dependabot.yml](../.github/dependabot.yml)）

`swift`（SPM）・`npm`（JS ツール）・`github-actions` の 3 エコシステムを監視する。

```yaml
version: 2
updates:
  - package-ecosystem: "swift"
    directory: "/"
    schedule: { interval: "weekly" }
  - package-ecosystem: "npm"
    directory: "/"
    schedule: { interval: "weekly" }
  - package-ecosystem: "github-actions"   # SHA 固定の自動更新（§8）
    directory: "/"
    schedule: { interval: "weekly" }
```

### GitHub Actions の SHA 固定（サプライチェーン対策）

ワークフローの `uses:` は **可変タグ（`@v4` 等）ではなくコミット SHA で固定**する。タグは付け替え可能なため、乗っ取られたアクションが同じタグで悪性コードを配布する攻撃を防げない。

```yaml
# NG（タグは可変 → すり替えられうる）
- uses: actions/checkout@v4
# OK（コミット SHA で固定。コメントは可読性のための版表記）
- uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
```

SHA は GitHub API で取得する: `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`。
固定すると更新が止まるが、上記 Dependabot の `github-actions` がハッシュと版コメントを自動更新するため鮮度は保てる。

### CodeQL

GitHub の "Code scanning" を有効化し、Swift 言語を選択（GitHub Actions のセットアップウィザード経由が簡単）。

---

## 8. CI/CD：GitHub Actions

### 実行順（パイプラインの考え方）

```
1. mise install      … Swift 本体 + 補助ツールを mise.toml のバージョンで一括導入
2. swift format lint … 整形違反チェック（速い・最初に落とす）
3. swiftlint         … 危険パターン検出
4. swift build       … ビルド（= 型・並行性チェックを兼ねる）
5. swift test        … テスト
6. （リリース時）署名 + notarization
```

### ワークフロー雛形（`.github/workflows/ci.yml`）

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  build-test:
    runs-on: macos-26          # ※ 入手性は要確認（DESIGN §8）。未提供ならセルフホスト
    steps:
      # サプライチェーン対策: タグではなくコミット SHA で固定（コメントは版表記）
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
      - name: Setup mise (Swift + tools from mise.toml)
        uses: jdx/mise-action@e6a8b3978addb5a52f2b4cd9d91eafa7f0ab959d # v4.2.0
      - name: Format check
        run: swift format lint --recursive Sources Tests
      - name: Lint
        run: swiftlint --strict    # バージョンは mise.toml で固定済み
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

> **macOS 26 ランナーの入手性は要確認**（[DESIGN §8 未確定事項](./DESIGN.md)）。GitHub 提供がなければセルフホストランナー（Apple silicon Mac）を用意する。

### 署名 / notarization（リリース時）

Developer ID 署名 + notarization は App Sandbox 無効配布（[DESIGN §5](./DESIGN.md)）の必須要件。最初は手動でも可。複雑化したら Fastlane の導入を検討（それまでは不要）。

---

## 9. ドキュメント/テキスト品質：cspell / secretlint / textlint

日英混在のドキュメントが多く、OSS として公開するため、テキスト品質と機密漏洩を機械的に守る。これらは JS 製ツールで、**Node・pnpm は mise で管理**する（§1）ので新たなバージョン管理ツールは増やさない。

| ツール | 目的 | 設定ファイル |
| --- | --- | --- |
| **cspell** | 英語の誤字脱字（ドキュメント + Swift コメント） | `cspell.json` |
| **secretlint** | 資格情報（証明書・トークン等）の誤コミット防止 | `.secretlintrc.json` |
| **textlint** | 日本語の表記ゆれ・冗長表現・ら抜き等 | `.textlintrc.json` + `prh.yml` |
| **lefthook** | コミット前にまとめて実行（変更ファイルのみ） | `lefthook.yml` |

### インストール

```sh
mise install            # node + pnpm（mise.toml）
pnpm install            # package.json の devDependencies + フック有効化（prepare: lefthook install）
```

### 実行

```sh
pnpm run lint:spell     # cspell（英語スペル）
pnpm run lint:text      # textlint（日本語 prose）
pnpm run lint:text:fix  # textlint 自動修正
pnpm run lint:secret    # secretlint（機密検出）
pnpm run lint           # 上記まとめて
```

### 設計上のポイント

- **cspell の日本語対応**: `cspell.json` の `ignoreRegExpList` で**日本語（ひらがな/カタカナ/漢字）とコードブロックを除外**し、英単語だけを検査する。固有名詞（`apiserver`, `vmnet`, `swiftlint` 等）は `words` 辞書に登録済み。IDE の「Unknown word」ノイズもここで解消する。
- **textlint は緩めから**: `preset-ja-technical-writing` を**一部緩和**（文長 120 字・ですます/である混在チェック off 等）して導入。既存ドキュメントが大量のエラーとならないよう抑えつつ、運用しながら厳格化する。表記ゆれは `prh.yml`（GitHub / macOS / サーバ など）で吸収。
- **secretlint は「最後の砦」**: 検出漏れもあるため過信しない。**コミット済み履歴の機密は別途対応**が必要（このフックは新規コミットを守るもの）。署名証明書・notarization 資格情報・レジストリトークン（[DESIGN §5](./DESIGN.md)）が主な防御対象。
- **変更ファイルのみをコミット前フックで、全文走査は CI へ**: `lefthook.yml` で `{staged_files}` に絞って高速化し、全文走査を CI（§8 とは別の `quality.yml`）に寄せる。

### textlint MCP による AI 自己レビュー

textlint は **MCP サーバ**を内蔵しており（`npx textlint --mcp`）、Claude Code などの AI から lint / fix を直接呼べる。本リポジトリは [.mcp.json](../.mcp.json) に `textlint` サーバを登録済みで、AI が**生成・編集した日本語テキストを自分で校正してから完了する**運用にしている（規約は [CLAUDE.md](../CLAUDE.md)）。

```json
// .mcp.json
{
  "mcpServers": {
    "textlint": { "type": "stdio", "command": "npx", "args": ["textlint", "--mcp"] }
  }
}
```

**有効化の順序**（MCP サーバは Claude Code 起動時に読み込まれる）:

```sh
mise install          # node / pnpm
pnpm install          # textlint 本体を導入（MCP サーバの実体）
# → Claude Code を再起動し、textlint サーバの利用を許可する
```

> 接続前は MCP ツールが使えないため、AI は代替として `pnpm exec textlint <file>` を実行してレビューする（[CLAUDE.md](../CLAUDE.md) に明記）。

### CI（OS 非依存なので Linux ランナーで全文走査）

JS 製ツールは OS 非依存のため、**安価な `ubuntu-latest`** で実行する（macOS ランナーは Swift ビルド用に温存）。ワークフローは [.github/workflows/quality.yml](../.github/workflows/quality.yml) に分離。

```yaml
jobs:
  text-quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
      - uses: jdx/mise-action@e6a8b3978addb5a52f2b4cd9d91eafa7f0ab959d # v4.2.0
      - run: pnpm install --frozen-lockfile
      - run: pnpm run lint:secret
      - run: pnpm run lint:spell
      - run: pnpm run lint:text
```

> **バージョンについて**: `package.json` の版指定は出発点。`pnpm install` が生成する `pnpm-lock.yaml` をコミットして固定する。最新へ上げる場合は `pnpm up --latest` 後にロックファイルを更新する。

### サプライチェーン対策：minimumReleaseAge

npm の汚染パッケージ（公開直後に攻撃コードを仕込む手口）を踏み抜かないよう、**公開から一定時間が経過した版だけをインストール**する設定を入れている。設定は [pnpm-workspace.yaml](../pnpm-workspace.yaml) に置く（pnpm 10.16+ は設定をここへ集約）。

```yaml
# pnpm-workspace.yaml
minimumReleaseAge: 1440   # 公開から 1440 分（1 日）経過した版のみ許可
# minimumReleaseAgeExclude:   # 即時に入れたい例外があれば名前単位で列挙
#   - "some-internal-package"
```

- **効果**: 悪性リリースの多くは公開から 1 時間以内に発見・削除される。1 日空ければ実用上ほぼ防げる。より慎重にするなら `4320`（3 日）等へ。
- **transitive にも適用**: 直接依存だけでなく、依存の依存（推移的依存）にも効く。
- **必要バージョン**: この設定は **pnpm 10.16+**、**pnpm 11 では既定で 1440 が有効**。本プロジェクトは [mise.toml](../mise.toml) で `pnpm = "11"`、[package.json](../package.json) の `packageManager` も `pnpm@11` 系に固定している（pnpm 9 では機能しないため）。
- **CI との関係**: CI は `pnpm install --frozen-lockfile` でロックファイル固定のため、この遅延はローカルでの `install` / `up` 時に効く。

---

## 10. エディタ

- **Xcode**: SwiftUI プレビュー・UI テスト・署名/配布に必須。GUI 開発の主力。
- **VS Code + Swift 拡張**: 軽量編集・mise 連携・バックグラウンドインデックス対応。CLI/パッケージ中心の作業に。

両方を併用し、「UI と配布は Xcode、ロジックとパッケージは VS Code/CLI」と使い分けると快適。

---

## 11. 初回セットアップ手順（まとめ）

```sh
# 1. mise を入れる
curl https://mise.run | sh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc   # 新しいシェルを開く

# 2. Swift 本体 + 補助ツール + node/pnpm を mise.toml のバージョンで一括導入
mise install
# swift-format は Swift 同梱（`swift format` で利用可）

# 3. JS 製テキスト品質ツールを導入 + Git フックを有効化
pnpm install                       # cspell / secretlint / textlint / lefthook（prepare で lefthook install）

# 4. ビルド & テスト（雛形が揃ったら）
swift build
swift test

# 5. 整形 & lint（Swift）
swift format --in-place --recursive Sources Tests
swiftlint --fix

# 6. テキスト品質チェック（ドキュメント）
pnpm run lint
```

---

*この構成は最小から始め、必要になった時点で拡張する方針。過剰投資を避け、まずは「ビルドが通り、lint/format/test が CI で回る」状態を Phase 0 のゴールにする（[DESIGN §6 ロードマップ](./DESIGN.md)）。*
