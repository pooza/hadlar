module Hadlar
  # 自分から絡む形（#25）の運用操作。
  class TeaseCommand < Thor
    include Package

    def self.exit_on_failure?
      return true
    end

    # 🔴 **投稿しない・LLM を呼ばない**（課金なし・#35）。ホームを引いて、絞り込みの結果だけを見せる。
    # ⚠ 本文は出さない（URL と理由だけ）。⚠ **一覧は CLI 用に別に持ち、痕跡に書かない**（makoto2#640）。
    desc 'preview', 'ホームを引いて、絡む候補の絞り込みの結果を表示する（投稿しない・課金なし）'
    option :all, type: :boolean, default: false, desc: '落とした投稿も理由つきで表示する'
    def preview
      statuses = mastodon.home_timeline
      passed = 0
      statuses.each do |status|
        reason = candidates.reason(status)
        passed += 1 unless reason
        next if reason && !options[:all]
        puts "#{reason || 'ok'} @#{status.dig('account', 'acct')} #{status['url'] || status['uri']}"
      end
      puts "#{passed} / #{statuses.size} passed"
    rescue Ginseng::Error => e
      fail_with("ホームを引けませんでした: #{error_message(e)}")
    end

    # 🔴 **投稿しない。**見かけた投稿として LLM に渡し、絡む一言を表示するだけ（#37・指示書の手直し）。
    # ⚠ **課金がある**（1 回 約 $0.003〜0.04）。⚠ 門（`TeaseGate`）も通らない（回数に数えない）。⚠ 常駐の痕跡に書かない（`quiet!`）。
    desc 'try TEXT', '見かけた投稿として絡ませて表示する（投稿しない・課金あり）'
    def try(text)
      fail_with('API キーがありません（config/local.yaml の /anthropic/api_key）') unless ChatModel.enabled?
      reply = model.tease(text)
      fail_with('返事を作れませんでした（ログを見てください）') unless reply
      puts reply.silent? ? '(絡まない)' : reply.text
      puts usage_line(reply.usage)
    end

    # 🔴 **例題を全部流す**（#37）。⚠ **課金がある**（例題 1 件につき 1 回）。🔴 合格の線は「silent が全部空」。
    desc 'eval', '例題を流して、絡まないはずの投稿に絡まないかを確かめる（投稿しない・課金あり）'
    option :file, type: :string, default: 'config/chat/tease_examples.yaml', desc: '例題の YAML'
    def eval
      fail_with('API キーがありません（config/local.yaml の /anthropic/api_key）') unless ChatModel.enabled?
      failed = YAML.load_file(File.expand_path(options[:file], Environment.dir)).count do |example|
        !judge(example)
      end
      puts failed.zero? ? 'OK' : "NG: #{failed}"
      exit 1 unless failed.zero?
    end

    # 🔴 **こちらから絡まない相手に載せる**（#39）。⚠ 本人が返事で頼めば自動で載る（印 `leave_alone`）。⚠ 返事は止めない。
    desc 'off ACCT', 'こちらから絡まない相手に載せる（返事は続ける）'
    def off(acct)
      found = mastodon.lookup_account(acct)
      fail_with("アカウントが見つかりません: #{acct}") unless found
      fail_with("もう載っています: @#{found['acct']}") if repository.opted_out(found['id'])
      repository.opt_out(found['id'], found['acct'])
      puts "off: @#{found['acct']} (id: #{found['id']})"
    end

    # 🔴 **戻すのはオーナーの CLI だけ**（0.2・#25）。
    desc 'on ACCT', 'こちらから絡まない相手から外す'
    def on(acct)
      # ⚠ 載せたときの acct で引けなければ、Mastodon で引き直して ID で探す（`chat unblock` と同じ）。
      row = repository.find_optout_by_acct(acct)
      row ||= (found = mastodon.lookup_account(acct)) && repository.opted_out(found['id'])
      fail_with("載っていません: #{acct}") unless row
      repository.opt_in(row[:account_id])
      puts "on: @#{row[:acct]}"
    end

    desc 'list', 'こちらから絡まない相手の一覧'
    def list
      rows = repository.all_optouts
      return puts('(none)') if rows.empty?
      rows.each {|row| puts "@#{row[:acct]} since #{row[:opted_out_at]}"}
    end

    private

    # ⚠ テストが差し替える（`@repository`）。
    def repository
      @repository ||= ChatRepository.new
      return @repository
    end

    # @return [Boolean] 合格か
    def judge(example)
      reply = model.tease(example.fetch('text'))
      unless reply
        puts "ERROR #{example['text']}"
        return false
      end
      ok = example['expect'] != 'silent' || reply.silent?
      puts "#{ok ? 'ok' : 'NG'} [#{example['expect']}] #{example['text']}"
      puts "    → #{reply.silent? ? '(絡まない)' : reply.text}"
      return ok
    end

    def usage_line(usage)
      return "tokens: #{usage[:input_tokens]} / #{usage[:output_tokens]}" \
        " (cache read #{usage[:cache_read]} / write #{usage[:cache_write]}・約 $#{model.cost(usage)})"
    end

    # ⚠ **常駐の痕跡に書かない**（#28）。
    def model
      @model ||= ChatModel.new.quiet!
      return @model
    end

    def candidates
      @candidates ||= TeaseCandidates.new(
        own_id: mastodon.account['id'],
        followed_by: ->(id) {roster.include?(id)},
      )
      return @candidates
    end

    def roster
      @roster ||= FollowerRoster.new(record: false)
      return @roster
    end

    def fail_with(message)
      warn message
      exit 1
    end

    # ⚠ テストが差し替える（`@mastodon`）。
    def mastodon
      @mastodon ||= MastodonService.new
      return @mastodon
    end
  end
end
