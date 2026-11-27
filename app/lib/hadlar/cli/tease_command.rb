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

    private

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
