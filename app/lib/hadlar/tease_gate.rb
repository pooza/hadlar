module Hadlar
  # 自分から絡むかの門（#36・設計は #25）。⚠ **黙って可否だけ返す** — `ChatGate#decide` と違い、決まった文を返さない
  # （話しかけていない相手へ「フォローしてから」「上限です」を送らない）。
  #
  # - 🔴 **既定は閉じている**（`/chat/tease/enabled: false`）。⚠ `/chat/enabled: false`（困ったときの止め方）でも閉じる
  # - 🔴 **上限は試行（LLM を呼んだ回数）で持つ** — 「迷ったら絡まない」が効くほど呼び出しが増えるため（v1 が黙った返事も
  #   数えるのと同じ理由）。投稿の上限と最小間隔は別に見る
  # - ⚠ **抽選**: 巡回ごとに確率 `chance` で 1 件だけ。まず人を一様に選び、その人の最新の 1 件（多く書く人に偏らせない）。
  #   ⚠ 入れないと毎回「巡回の直前に書いた人」に当たる
  # - ⚠ 窓はどれも「今から遡る」幅（`ChatGate` と同じ）。時間帯の制限は設けない（オーナー 2026-11-28）
  # - 記録は `chat_event` の kind（`tease_try` ＝ LLM を呼んだ・`tease` ＝ 投稿した）
  class TeaseGate
    include Package

    TRY = :tease_try
    POST = :tease
    DAY = 86_400

    # @param repository [ChatRepository, nil] ⚠ テストが差し替える
    # @param random [Random, nil] ⚠ テストが差し替える
    def initialize(repository: nil, random: nil)
      @repository = repository
      @random = random || Random.new
    end

    def self.enabled?
      config = Config.instance
      return config['/chat/enabled'] == true && config['/chat/tease/enabled'] == true
    end

    # 閉じている理由。⚠ **開いていれば nil。**
    # @return [Symbol, nil]
    def closed_reason(now = Time.now)
      return :disabled unless self.class.enabled?
      return :try_limit if repository.count(TRY, now - DAY) >= limit('try_per_day')
      return :post_limit if repository.count(POST, now - DAY) >= limit('post_per_day')
      return :post_interval if posted?(now - duration('limit/post_interval'))
      return nil
    end

    # 候補（`TeaseCandidates` を通ったもの）から 1 件を選ぶ。⚠ **外れたら nil**（抽選・相手ごとの間隔）。
    # @param statuses [Array<Hash>]
    # @return [Hash, nil]
    # 🔴 **一度試した投稿は選ばない**（再起動しても・相手ごとの間隔が対象の古さより短い設定でも）。
    def pick(statuses, now = Time.now)
      statuses = statuses.reject {|status| repository.recorded_status?(TRY, status['id'])}
      return nil if statuses.empty?
      return nil unless @random.rand < chance
      by_account = statuses.group_by {|status| status.dig('account', 'id').to_s}
      ids = by_account.keys.reject {|id| resting?(id, now)}
      return nil if ids.empty?
      return by_account[ids.sort[@random.rand(ids.size)]].max_by {|status| status['id'].to_i}
    end

    def record_try(status, now = Time.now)
      record(status, TRY, now)
    end

    def record_post(status, now = Time.now)
      record(status, POST, now)
    end

    private

    # 相手ごとの間隔の中か（試行は 1 日に 1 回・投稿は 3 日に 1 回）。
    def resting?(id, now)
      return true if tried?(now - duration('limit/account/try_interval'), id)
      return posted?(now - duration('limit/account/post_interval'), id)
    end

    def tried?(since, id = nil)
      return repository.count(TRY, since, account_id: id).positive?
    end

    def posted?(since, id = nil)
      return repository.count(POST, since, account_id: id).positive?
    end

    def record(status, kind, now)
      account = status['account'] || {}
      status_id = status['id'] if kind == TRY
      repository.record(account['id'], account['acct'], kind, now, status_id: status_id)
    end

    def chance
      value = config['/chat/tease/chance']
      return value.to_f if value.is_a?(Numeric) && value.between?(0, 1)
      raise Ginseng::ConfigError, "tease: bad chance '#{value}'"
    end

    def limit(key)
      count = config["/chat/tease/limit/#{key}"]
      return count if count.is_a?(Integer) && count.positive?
      raise Ginseng::ConfigError, "tease: bad limit #{key} '#{count}'"
    end

    def duration(key)
      value = config["/chat/tease/#{key}"]
      seconds = Fugit::Duration.parse(value.to_s)&.to_sec
      return seconds if seconds&.positive?
      raise Ginseng::ConfigError, "tease: bad #{key} '#{value}'"
    end

    def repository
      @repository ||= ChatRepository.new
      return @repository
    end
  end
end
