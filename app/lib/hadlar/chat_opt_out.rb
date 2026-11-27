module Hadlar
  # 本人が「絡むな」と頼んだときの扱い（#39・→ `ChatResponder`）。⚠ `ChatResponder` から切り出した（`Metrics/ClassLength`）。
  # ⚠ `repository` / `pick` / `post_reply` / `done` は取り込む側のもの。
  module ChatOptOut
    OPTOUT_NOTICE_TYPE = 'tease_optout'.freeze

    private

    # 🔴 **「絡むな」と頼まれたら、以後こちらからは絡まない**（#39）。⚠⚠ **返事は決まった文に差し替える** — モデルの文のまま
    # だと「分かった」と言ったのに印が付かず絡み続ける、という食い違いが起こりうる（いちばん本当に怒らせる形）。
    # ⚠ 原稿が無ければ黙る（載せるのは止めない）。⚠ 返事そのものは止めない（ペナルティではない）。
    def opt_out(account, status, thread, notification)
      repository.opt_out(account['id'], account['acct'])
      body = pick(OPTOUT_NOTICE_TYPE)
      post_reply(account, status, body, thread) if body
      return done(:tease_optout, notification)
    end
  end
end
