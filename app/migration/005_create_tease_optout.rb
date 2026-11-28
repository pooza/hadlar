Sequel.migration do
  # 自分から絡まない相手（#39）。🔴 **本人が返事で「絡むな」と頼んだら載る**（印 `leave_alone`）。⚠ 戻すのはオーナーの CLI だけ
  # （`hadlar tease on ACCT`・0.2）。⚠ 返事は止めない（話しかけられたら今までどおり返す）。
  #
  # ⚠ **鍵は Mastodon のアカウント ID**（acct は変えられる・`chat_block` と同じ）。⚠ 本文は持たない。
  change do
    create_table(:tease_optout) do
      String :account_id, primary_key: true
      String :acct, null: false
      DateTime :opted_out_at, null: false
    end
  end
end
