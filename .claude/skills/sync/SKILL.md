---
name: sync
description: セッション開始時の進捗同期。「進捗を同期してください」「同期して」などで起動する。リモート・実機（CT）・Dependabot・Codex レビュー・chubo2・pooza/makoto2 との往復を確認して報告する。
---

# セッション開始時の同期手順

⚠ **この手順の正本はこのファイル。**雛形は pooza/makoto2 の同期スキル（`6475906`）で、ハドラーブロスに要らない段（曲データ・誕生日の原稿・cure-api など）は落としてある。
「なぜそうするか」と踏んだ記録は `docs/CLAUDE.md` に残す。手順を足すときはここだけを直す。

🔴 **この手順の本体は読むだけ。**外へ書く段（コメント・返信・👍・起票・マージ・マイルストーンの書き換え）は、**読んだ結果を報告して判断を仰いでから**行う。

報告は日本語で書く。判断を仰ぐ問いも日本語。

## 1. 読む

- `docs/CLAUDE.md` を読む（`MEMORY.md` は自動で読まれるので、両者の食い違いを意識する）
- ⚠ **前のセッションの締めを読む**（メモリの経過ログ `project_hadlar-kickoff.md`）。「次は〜」と書いてあれば、そこが前提の答え合わせになる

## 2. リモート

```sh
git fetch origin                       # 🔴 最初に必ず。リモートが正本で、ローカルを信用しない
git log HEAD..origin/develop --oneline
git log --oneline -10
gh issue list --state open
gh pr list --state open
```

## 3. 実機（CT 2 台）

⚠ **CT はまだ無い**（pooza/chubo2#309 で依頼中・2026-11-13）。できたら、makoto2 の `hosts.sh` を雛形に、この段へ確認の手順を足す。それまでは 6. で #309 の状態だけを見る。

## 4. Dependabot

```sh
gh api repos/pooza/hadlar/dependabot/alerts -X GET -f state=open --jq 'length'
```

🔴 **`state=open` で絞る**（絞らないと `fixed` も返り、塞がったアラートを数える）。

## 5. Codex のレビュー

**最近マージされた PR と、いま open な PR の両方**を見る（⚠ 未返信がいちばん残りやすいのは open PR）。

```sh
gh pr list --state merged --limit 8 --json number --jq '.[].number'
.claude/skills/sync/scripts/codex.sh pooza/hadlar <PR 番号> ...   # 4 経路・読むだけ
```

- 🔴 **完了の判定はインラインごとの「返信 ＋ 👍」**。①未返信 → 指摘を読んで対応を判断し、返信 ＋ 👍 ②返信済みで 👍 なし → 👍 ③両方済み → 完了
- ⚠⚠ **PR への 👍 は「ある巡が指摘なしで終わった」印**であって、PR 全体が片付いた印ではない。⚠ **巡ごとに見る**（`Reviewed commit:` が巡を指す）
- ⚠ **👀（`eyes`）は「読み始めた」の合図で成果物ではない**
- ⚠ **自動のレビューは PR を開いた時と draft を ready にした時しか走らない。**後から積んだコミットを見てほしいときは `@codex review` とコメントする
- 🔴 **P2 は 1 巡だけ。**対応したら再レビューを頼まずに次へ（繰り返すと 10 巡いく）
- → 規約の正本は [`ginseng-style` の docs/workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md)

## 6. chubo2

```sh
git -C ../chubo2 fetch origin && git -C ../chubo2 log HEAD..origin/main --oneline
gh issue list --repo pooza/chubo2 --state open --search hadlar
```

- CT（#309）・レシピ・トークンなど、こちらの作業の前提になっている Issue が動いていないか
- ⚠⚠ **open / `updatedAt` だけで「動いていない」と判断しない。必ずコメントまで読む**（chubo2 は「作業は完了、モンキーテスト待ちで open」を常用する）
- 🔴 **11/1〜11/4 はインフラ作業が凍結される**（chubo2 側の取り決め）

## 7. pooza/makoto2（MAKOTO）との往復

```sh
gh issue list --repo pooza/makoto2 --state open --search "hadlar in:body" --json number,title,labels \
  --jq '.[] | "makoto2#\(.number) \(.title) [\([.labels[].name] | join(","))]"'   # こちらから出した依頼
gh issue list --state open --search "makoto2 in:body"                           # 向こうから来た依頼
git -C ../makoto2 fetch origin && git -C ../makoto2 log --oneline origin/develop -15 -- \
  app/lib/makoto/chat_\* app/lib/makoto/mention_\* app/lib/makoto/heartbeat_stream.rb \
  app/lib/makoto/heartbeat_chat.rb app/lib/makoto/model/chat_repository.rb config/chat
```

- チャットまわりは makoto2 から写したもので、同じ穴を両方で踏みうる。🔴 **情報交換の基本は Issue**（片方で直したら「同じ直しが要るか」を相手のリポジトリに出し、元のコミットか PR を指す）。セッション間のメッセージはその場の質問だけ
- 見るのは 3 つ: ①**こちらから出した依頼の状態** ②**向こうから来た依頼**（マイルストーンが空のまま放置されていないか）③**makoto2 のチャットまわりに入った直し**（Issue が来ていなくても、こちらに要るかを見る）
- 🔴 **makoto2 の作業はこちらで肩代わりしない**（答える・依頼するまで）

## 8. 報告とメモリ

- メモリの経過ログ（`project_hadlar-kickoff.md`）に、その日の同期の結果を足す（索引の `MEMORY.md` には積まない）
- 報告は「見たもの」「判断してほしいこと」「その他」に分ける。⚠ **判断を仰ぐものは、問いだけ読んで答えられるように書く**
