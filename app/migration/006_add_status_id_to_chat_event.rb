Sequel.migration do
  # 自分から絡んだ投稿（#40）。🔴 **同じ投稿に 2 度 LLM を呼ばない**（再起動でプロセスの記憶が消えても）。
  # ⚠ 入れるのは `tease_try` だけ（ほかの kind は nil）。⚠ 本文は持たない（ID だけ）。
  # ⚠ 行は試行のたびに 1 行のまま（1 日 6 回まで・増え方は変わらない）。
  change do
    alter_table(:chat_event) do
      add_column :status_id, String
      add_index [:kind, :status_id]
    end
  end
end
