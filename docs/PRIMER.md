# 技術プライマー — 本プロジェクトを支える基盤技術の学習資料

> 対象読者: 本プロジェクト（Apple Container Desktop）の開発・運用に関わる人。
> 目的: AI で実装を進めるとしても、**中身を理解していないと運用フェーズで破綻する**。本書は「最低限ここを押さえれば、生成されたコードを読み・直し・運用判断できる」ラインを、このプロジェクトの文脈に紐づけて解説する。
> 読み方: 各節は「**何か** → **なぜ本プロジェクトで重要か** → **運用で効いてくる点** → **さらに学ぶ**」の順。完璧な理解より「危険を察知できる地図」を持つことを優先する。

---

## 全体像 — この資料がカバーする3層

本アプリは、大きく3つの技術領域の上に成り立っている。どれか1つでも理解が欠けると、障害時に「どこを見ればいいか分からない」状態になる。

| 層 | 技術 | 本書の節 |
| --- | --- | --- |
| ① GUI アプリ本体 | Swift / SwiftUI / 並行性 / Process | §1〜§4 |
| ② アプリ ↔ container 連携 | XPC / ContainerAPIClient / CLI | §5〜§6 |
| ③ container が動く仕組み | Virtualization.framework / vmnet / launchd / OCI | §7〜§10 |

---

# 第I部: GUI アプリ本体（Swift / SwiftUI）

## §1. Swift の必須概念（このプロジェクトで頻出するものだけ）

**何か:** Swift はアップルの静的型付き言語。本プロジェクトで特に効くのは以下。

- **オプショナル（`?` / `!`）**: 「値が無いかもしれない」を型で表す。`!` の強制アンラップはクラッシュ源 → 運用上の事故の典型。
- **`struct`（値型）vs `class`（参照型）**: SwiftUI のモデルは原則 `struct`（コピーされる＝予期せぬ共有が起きない）。`class` は共有・参照され、ライフサイクル管理が必要。
- **プロトコル**: インターフェイス。本プロジェクトの心臓部 `ContainerBackend` はプロトコルで、実装（XPC/CLI/モック）を差し替え可能にしている（[DESIGN §2.2](./DESIGN.md)）。
- **`enum` + 関連値**: 状態やエラーを型安全に表現。`BackendError.unsupported` のように「失敗の種類」を列挙する。
- **`Result` / `throws` / `try`**: エラーは戻り値ではなく `throw`。呼び出し側は `try`/`do-catch` で扱う。

**なぜ重要か:** 生成されたコードのバグの多くは「nil の扱い」「値型/参照型の取り違え」「エラーの握りつぶし」に集約される。ここを読めれば AI 生成コードのレビューができる。

**運用で効いてくる点:** クラッシュログに `unexpectedly found nil` や `Fatal error` が出たら、強制アンラップ(`!`)を疑う。

**さらに学ぶ:** [The Swift Programming Language（公式・無料）](https://docs.swift.org/swift-book/)

---

## §2. 並行性 — async/await・actor・AsyncStream（最重要・事故多発地帯）

**何か:** Swift の現代的な非同期処理。本プロジェクトは「コンテナ一覧の取得」「ログのストリーム」など非同期処理だらけ。

- **`async`/`await`**: 「時間のかかる処理」を、ブロックせずに待つ書き方。
  ```swift
  let containers = try await backend.listContainers()  // 完了まで他をブロックしない
  ```
- **`Task`**: 非同期処理の実行単位。UI のボタン押下から `Task { ... }` で起動する。
- **`actor`**: **データ競合を型レベルで防ぐ**仕組み。内部状態へのアクセスが自動的に直列化される。本プロジェクトはバックエンドアクセスを actor で包み、「同時に複数の操作が状態を壊す」事故を防ぐ（[DESIGN §2.4](./DESIGN.md)）。
- **`Sendable`**: 「スレッドをまたいで安全に渡せる」ことを示すマーカー。Swift 6 の strict concurrency ではこれが**コンパイル時に強制**される。
- **`AsyncStream` / `AsyncThrowingStream`**: 「値が時間をかけて次々届く」流れ。ログ追従(`logs -f`)・統計(`stats`)・ビルド進捗はこれで表現する。
  ```swift
  for try await line in backend.logs(id: id, follow: true) {
      append(line)   // 1行届くたびに UI 更新
  }
  ```

**なぜ重要か:** Swift 6 の strict concurrency は厳しく、AI が「とりあえず動く」コードを書くと**コンパイルが通らない or 警告だらけ**になりがち。`Sendable`/`actor`/`@MainActor` の意味を分かっていないと、エラーメッセージの海で迷子になる。

**運用で効いてくる点:**
- UI 更新は必ずメインスレッド（`@MainActor`）で行う。ここを誤ると「たまに UI が固まる/更新されない」再現性の低いバグになる。
- ストリーム（ログ等）は**必ず終了処理（キャンセル）を書く**。書き忘れると Process が残り続けてリソースリーク → 運用中にメモリ・FD が枯渇する。

**さらに学ぶ:** [Swift Concurrency（公式ドキュメント）](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) / WWDC「Meet async/await」「Protect mutable state with Swift actors」

---

## §3. SwiftUI と状態管理（@Observable）

**何か:** 宣言的 UI フレームワーク。「状態（データ）を書けば、UI は自動で追従する」のが核心。

- **宣言的**: 「どう描くか」ではなく「状態がこうならこう見える」を書く。
- **`@Observable`（Observation フレームワーク, 新方式）**: ViewModel をこれで宣言すると、プロパティ変更が自動で UI に反映される。旧 `ObservableObject`/`@Published` の後継。
  ```swift
  @Observable final class ContainersViewModel {
      var containers: [Container] = []   // ここを変えると一覧が再描画される
      func reload() async { containers = try await backend.listContainers() }
  }
  ```
- **`NavigationSplitView`**: 本アプリの3ペイン（サイドバー/一覧/詳細）の骨格（[DESIGN §4.1](./DESIGN.md)）。
- **`@MainActor`**: ViewModel は UI を触るのでメインアクター上に置く。

**なぜ重要か:** 「データを直接いじれば画面が変わる」というモデルを理解しないと、「なぜ画面が更新されないのか」「なぜ無限に再描画されるのか」が分からない。

**運用で効いてくる点:** パフォーマンス問題の多くは「状態の持ちすぎ・更新範囲の広すぎ」。一覧2秒ポーリングで全行を作り直すと CPU を食う → 差分更新や表示中のみ購読、で抑える。

**さらに学ぶ:** [SwiftUI チュートリアル（公式）](https://developer.apple.com/tutorials/swiftui) / [Observation フレームワーク](https://developer.apple.com/documentation/observation)

---

## §4. プロセス起動 — Foundation.Process（CLI 連携の土台）

**何か:** 外部プログラム（ここでは `container` CLI）を起動し、入出力をやり取りする API。ハイブリッド方式の「CLI 側」の実体（[DESIGN §2.3](./DESIGN.md)）。

```swift
let p = Process()
p.executableURL = URL(filePath: "/usr/local/bin/container")
p.arguments = ["ls", "--format", "json"]
let out = Pipe(); p.standardOutput = out
try p.run()
let data = out.fileHandleForReading.readDataToEndOfFile()
// data を JSON デコード → ドメインモデルへ
```

**なぜ重要か:** XPC で未公開の操作（system/builder/DNS など）は CLI 経由が必須。Process の扱いは本プロジェクトの避けられない要素。

**運用で効いてくる点（事故りやすい順）:**
1. **パス解決**: ユーザの `PATH` に依存しない。絶対パス（`/usr/local/bin/container`）を基本にし、設定で上書き可能に。
2. **大量出力でのデッドロック**: stdout を読まずに `waitUntilExit()` するとパイプが詰まって固まる。**読み取りと終了待ちを並行**させる。
3. **ストリーム（`-f`）の終了**: フォロー系は明示的に `terminate()` しないとゾンビ化 → §2 のリーク問題と直結。
4. **stderr と exit code**: 失敗時は exit code と stderr をエラーに正規化（[DESIGN §2.3](./DESIGN.md)）。

**さらに学ぶ:** [Foundation.Process](https://developer.apple.com/documentation/foundation/process)

---

# 第II部: アプリ ↔ container 連携（XPC）

## §5. XPC とは — macOS のプロセス間通信（本プロジェクトの背骨）

**何か:** XPC（Cross-Process Communication）は、macOS で**別プロセスの機能を安全に呼び出す**ための仕組み。アップルが「権限分離（privilege separation）」のために設計した。

- macOS では機能をプロセスに分割するのが定石。例: 危険な処理を別プロセスに隔離し、片方がクラッシュしても本体は生きる。
- XPC は **launchd が管理**する（§9）。サービスはオンデマンドで起動され、使われなければ落とされる。
- やり取りは**メッセージ（辞書/シリアライズ可能なオブジェクト）**で行う。型付き API（プロトコル）を介す方式もある。

**container における XPC（ここが核心）:**

```
本アプリ ──XPC──▶ container-apiserver ──▶ plugins(XPCサービス群)
   │                  （launchd 管理）        /usr/local/libexec/container/plugins
   └─ ContainerAPIClient（Swiftライブラリ）が、この XPC 通信を型付きでラップしている
```

- `container` CLI も、本アプリも、**同じ apiserver に XPC で話しかける**クライアントにすぎない。
- `ContainerAPIClient` を使えば、CLI を起動せずに直接 apiserver と会話できる（速い・型安全）。
- ただし **1.0.0 で v0 系 XPC API の互換が削除**された＝**バージョン不一致は通信断の原因**となる。これは運用で最重要の注意点。

**なぜ重要か:** 「アプリが動かない」ときの切り分けが、XPC を理解しているかで天と地ほど変わる。
- apiserver が起動していない（launchd 未登録/停止）のか
- XPC のバージョン/権限が合わないのか
- そもそも CLI 経路の問題なのか

**運用で効いてくる点:**
- **バージョン整合性**: アプリがリンクした `ContainerAPIClient` のバージョンと、インストール済み `container` のバージョンがズレると XPC が通らない。→ 起動時に `container system version` でバージョン検証し、不一致を UI で警告する設計が要る（[DESIGN §5](./DESIGN.md) の「API 安定性」リスク）。
- **接続エラーの扱い**: XPC 接続は中断され得る（相手プロセスがクラッシュ/再起動）。再接続・タイムアウト・CLI フォールバックを実装する（[DESIGN §2.2](./DESIGN.md) の `HybridBackend`）。
- **コード署名**: XPC は接続元の署名を検証することがある。配布時の署名（§後述・Developer ID）が崩れると通信が拒否されうる。

**さらに学ぶ:** [XPC（公式）](https://developer.apple.com/documentation/xpc) / WWDC「Efficient and safe communication with XPC」 / [Anil Madhavapeddy の解説記事](https://anil.recoil.org/notes/apple-containerisation)

---

## §6. ハイブリッド連携の勘所（XPC + CLI の使い分け）

**何か:** 本プロジェクトは「XPC を主軸、未公開操作は CLI」というハイブリッド（[DESIGN §1.2 / §2.2](./DESIGN.md)）。ここは**設計判断が運用品質を直接左右する**ので独立して押さえる。

| 観点 | XPC 経路 | CLI 経路 |
| --- | --- | --- |
| 速度 | 速い（プロセス起動不要） | 遅い（毎回 Process 起動） |
| 型安全 | 高い（Swift API） | 低い（JSON 文字列をパース） |
| 安定性 | バージョン整合性に敏感 | CLI の出力フォーマット変更に敏感 |
| カバー範囲 | 一部未公開 | ほぼ全機能 |

**運用で効いてくる点:**
- **両経路で同じドメインモデルに収束**させる（[DESIGN §2.2](./DESIGN.md)）。でないと「XPC と CLI で取得結果が食い違う」という最悪のバグになる。
- **フォールバックは「黙って」やらない**。XPC 失敗→CLI 成功を続けると、XPC が壊れていることに気付けない。ログ/メトリクスに残す。
- CLI の `--format json` 出力は**将来のバージョンで変わりうる**。パーサは寛容に（未知フィールドを無視）作る。

---

# 第III部: container が動く仕組み（仮想化スタック）

> ここはアプリが直接触らない領域だが、**「なぜコンテナが起動しないのか」「なぜネットワークが繋がらないのか」を切り分けるには必須**。container は Docker と違い「1コンテナ = 1軽量VM」である点が最大の特徴。

## §7. コンテナと VM の違い、そして container の独自モデル

**何か:**
- **従来のコンテナ（Docker/Linux）**: 1つの Linux カーネルを共有し、プロセスを名前空間で隔離する。軽いが、ホストが Linux でないと動かない（macOS では裏で1つの大きな Linux VM を動かしていた）。
- **Apple container のモデル**: **コンテナごとに専用の軽量 Linux VM を立てる**。各コンテナが独立カーネルを持つ。

**なぜこの設計か（＝運用で効く理解）:**
- **強い隔離**: コンテナ間がVM境界で分離 → セキュリティが高い。
- **起動の速さ**: アップルが軽量化した VM + 専用 Linux カーネルで、VMながら高速起動を狙う。
- **代償**: コンテナごとに VM のオーバーヘッド（メモリ等）。**多数同時起動はホスト資源を食う** → [DESIGN §5](./DESIGN.md) の「多数 VM の負荷」リスクの根拠。

**運用で効いてくる点:** 「コンテナを10個立てたら Mac が重い」は仕様。stats ポーリングの間隔・対象を絞る設計（§2）がそのまま効く。

**さらに学ぶ:** [apple/container](https://github.com/apple/container) / [Containerization framework](https://github.com/apple/containerization)

---

## §8. Virtualization.framework と vmnet

**Virtualization.framework（何か）:** アップル製の、Apple silicon 上で**軽量に VM を作る**高水準フレームワーク。container はこれで各コンテナの Linux VM を生成・管理する。macOS 26+ / Apple silicon 限定という本プロジェクトの動作要件は、ここに由来する。

**vmnet（何か）:** VM に仮想ネットワーク（IPアドレス・NAT・ホスト⇔VM通信）を提供するフレームワーク。コンテナのポート公開（`-p 8080:8080`）やコンテナ間通信はこの層が支える。

**運用で効いてくる点:**
- **ネットワーク不通の切り分け**: 「ポートに繋がらない」時、原因は ①コンテナ内アプリ ②ポートフォワード設定 ③vmnet/ネットワーク設定 のどこか。層を意識すると切り分けが速い。
- **vmnet は特権を要する**ことがあり、権限・ネットワーク設定が絡むトラブルの温床。macOS のネットワーク権限ダイアログを疑う。
- **macOS 26 のネットワーク機能**に依存する操作（user-defined network など）があり、OS バージョンが要件を満たさないと機能が欠ける。

**さらに学ぶ:** [Virtualization framework](https://developer.apple.com/documentation/virtualization)

---

## §9. launchd — macOS のサービス管理

**何か:** macOS の**全プロセス/サービスの親玉**（init 相当）。デーモン・エージェント・XPCサービスの起動・常駐・再起動を管理する。

- `container-apiserver` は launchd の管理下で動く。`container system start/stop` は実質、この launchd 登録の操作。
- XPC サービスは launchd が**オンデマンドで起動**する（呼ばれたら立ち上げ、不要なら落とす）。

**なぜ重要か:** 「apiserver が動いていない」系トラブルの本丸。GUI の「ワンクリック起動」（[DESIGN §4.4 オンボーディング](./DESIGN.md)）は内部的に launchd 経由の `system start` を呼ぶ。

**運用で効いてくる点:**
- 状態確認: `container system status`、ログ: `container system logs`（内部は Unified Logging）。
- launchd 登録の破損や古いバージョンの残留があると、起動失敗・バージョン不整合を招く。アップデート時は登録の入れ替えに注意。

**さらに学ぶ:** `man launchd` / `man launchctl` / [Apple: Creating launchd agents/daemons](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/Introduction.html)

---

## §10. OCI イメージとレジストリ

**何か:** OCI（Open Container Initiative）はコンテナイメージ/レジストリの**標準仕様**。container はこれに準拠するため、Docker Hub など既存レジストリと相互運用できる。

- **イメージ**: レイヤ（差分の積み重ね）+ マニフェスト（構成）+ コンフィグ。`pull` でレイヤをダウンロードし、`build` でレイヤを生成する。
- **レジストリ**: イメージの配布先。`registry login` の資格情報は **Keychain** に保存される（[DESIGN §1.1](./DESIGN.md)）。
- **build は BuildKit 経由**で、container では builder（BuildKit）プロセスを別途起動する必要がある（[DESIGN §1.2](./DESIGN.md)）。

**運用で効いてくる点:**
- `pull` が遅い/失敗 → ネットワーク or レジストリ認証 or レイヤキャッシュを疑う。
- `build` が動かない → **builder が起動しているか**を最初に確認（GUI で自動起動を促す設計）。
- 資格情報は Keychain にあるので、消えた/壊れた時は Keychain を見る。

**さらに学ぶ:** [OCI 仕様](https://github.com/opencontainers/image-spec) / [BuildKit](https://github.com/moby/buildkit)

---

# 第IV部: 学習の進め方

## §11. 推奨学習ルート（最短で「読めて・直せて・運用判断できる」状態へ）

1. **手を動かして container を触る（半日）**: `container system start` → `run`/`ls`/`logs`/`exec`/`stop` を一通り。`--format json` の出力を眺める。← アプリが裏で何を呼ぶかの体感。
2. **Swift 並行性（§2）を集中的に（1〜2日）**: ここが一番事故る。WWDC の async/await・actors 動画 + 公式 Concurrency 章。
3. **SwiftUI + Observation（§3）でミニ一覧アプリ（1日）**: 「状態→UI追従」を体で覚える。
4. **XPC の概念（§5）を読み物として（半日）**: 自前実装は不要。「誰が誰に話しかけ、何が壊れうるか」の地図を持つ。
5. **仮想化スタック（§7〜§10）は障害時のリファレンスとして**: 通読より「困った時に戻る」使い方。

## §12. 「破綻」を避けるチェックリスト（運用で見る勘所）

- [ ] クラッシュ → 強制アンラップ(`!`)・並行性違反を疑う（§1, §2）
- [ ] UI が更新されない/固まる → `@MainActor`・更新範囲を疑う（§2, §3）
- [ ] メモリ/FD リーク → ストリーム/Process のキャンセル漏れを疑う（§2, §4）
- [ ] アプリが container に繋がらない → apiserver 稼働(launchd)・バージョン整合・署名を疑う（§5, §9）
- [ ] XPC が静かに失敗し CLI に流れ続けている → フォールバックのログ/可観測性（§6）
- [ ] コンテナ起動が重い → 1コンテナ1VMの仕様・stats ポーリング設計（§7, §2）
- [ ] ネットワーク不通 → アプリ/ポートフォワード/vmnet の層を切り分け（§8）
- [ ] build 失敗 → builder(BuildKit) 起動の有無（§10）

---

## 付録: 用語ミニ辞典

| 用語 | 一言で |
| --- | --- |
| XPC | macOS の安全なプロセス間通信。container 連携の背骨 |
| launchd | macOS のサービス管理の親玉。apiserver を起動・常駐させる |
| apiserver | `container-apiserver`。コンテナ操作の実体。XPC で話しかける相手 |
| ContainerAPIClient | apiserver と XPC で話す Swift ライブラリ（CLI 不要の型付き API） |
| Virtualization.framework | Apple silicon で軽量 VM を作るフレームワーク |
| vmnet | VM に仮想ネットワークを提供するフレームワーク |
| OCI | コンテナイメージ/レジストリの標準仕様 |
| BuildKit | イメージビルドのエンジン。container では builder として別起動 |
| actor | Swift のデータ競合防止の仕組み（アクセスを直列化） |
| Sendable | スレッド間で安全に渡せることを示す印（Swift 6 で強制） |
| @Observable | 状態変更を UI に自動反映させる SwiftUI の仕組み |
| AsyncStream | 値が次々届く非同期の流れ（ログ・統計・進捗に使う） |

---

*この資料は [DESIGN.md](./DESIGN.md) の設計判断の「なぜ」を支える背景知識をまとめたもの。設計書とセットで読むと、各設計判断（ハイブリッド連携・actor・ポーリング・署名）がどの技術的制約から来ているかが繋がる。*
