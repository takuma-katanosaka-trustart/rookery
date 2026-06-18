# Apple Container Desktop — プロジェクト規約

## テキスト生成時の自己レビュー（textlint）

このリポジトリの日本語テキスト（特に `**/*.md`）を**新規作成・編集したら、完了とする前に textlint で自己校正し、指摘を修正する**こと。

- **使うツール**: textlint MCP サーバ（[.mcp.json](.mcp.json) の `textlint`）。生成・編集したファイルパスを渡して lint / fix 提案を取得する。
- **MCP が未接続のとき**（初回・要再起動時など）は、代替として `pnpm exec textlint <対象ファイル>` を実行して結果を確認する。
- **修正方針**:
  - 自動修正できる表記ゆれ等は `pnpm run lint:text:fix`（または MCP の fix 提案）で直す。
  - 文意・構成に関わる指摘は、機械的に従わず内容を判断して修正する。
- **ルール定義**: ルートの [.textlintrc.json](.textlintrc.json) + [prh.yml](prh.yml)。誤検出が多いルールは設定側を調整する（ルールに振り回されない）。
- **対象外**: コードブロック・インラインコード・URL は textlint が元々除外する。英語の誤字は cspell（[cspell.json](cspell.json)）側で見る。

> 開発ツールチェーン全体の方針は [docs/TOOLING.md](docs/TOOLING.md) を参照。
