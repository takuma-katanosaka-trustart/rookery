#!/usr/bin/env bash
# PostToolUse フック: 生成・編集した Markdown を textlint で自己レビューし、
# 指摘を additionalContext として Claude にフィードバックする（非ブロッキング）。
#
# 何もしないケース（黙って exit 0）:
#   - 対象が Markdown 以外
#   - 対象がこのプロジェクト配下でない
#   - textlint が未インストール（node_modules/.bin/textlint が無い）
#   - ファイルが存在しない / パスを取得できない
set -uo pipefail

input=$(cat)
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)

[ -n "$f" ] || exit 0
case "$f" in
  "$PWD"/*) ;;          # プロジェクト配下のみ
  *) exit 0 ;;
esac
case "$f" in
  *.md) ;;              # Markdown のみ
  *) exit 0 ;;
esac
[ -f "$f" ] || exit 0
[ -x node_modules/.bin/textlint ] || exit 0   # 未インストールなら何もしない

out=$(pnpm exec textlint "$f" 2>&1)
status=$?
[ "$status" -eq 0 ] && exit 0   # 指摘なし

jq -n --arg ctx "textlint の指摘があります ($f)。内容を確認し、妥当なものは修正してください:
$out" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
