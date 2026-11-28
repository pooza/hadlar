module Hadlar
  # 自分から絡む常駐のスレッド（#38・設計は #25）。巡回 → 門 → 絞り込み → 抽選 → LLM → 投稿（または下書き）。
  #
  # - 🔴 **起こすのは開いているときだけ**（`/chat/tease/enabled`・`/chat/enabled`・キー）。⚠ 既定は閉じている
  # - 🔴 **下書きモード**（`/chat/tease/draft`・既定 true）: 投稿する代わりに、候補の URL と下書きをオーナーへ DM する。
  #   ⚠ 実際のフォロワーの投稿でさじ加減を見てから、本番で切り替える（#25）。⚠ 下書きも上限・間隔に数える（本番と同じ頻度で見る）
  # - 🔴 **返すのは `unlisted`** — 対象は `public` だけ（→ `TeaseCandidates`）だが、タイムラインを埋めない
  # - 🔴 **本文の `@` はメンションにしない**（`ChatThread.unmention`）。宛先の `@相手` だけを付ける
  # - ⚠ **同じ投稿に 2 度絡まない**（冪等キー `hadlar-tease-<status_id>`・相手ごとの間隔）
  # - 🔴 **スレッドを死なせない**（makoto2#611）。巡回が落ちてもログと Sentry に残して次の巡回へ
  # - ⚠⚠ **相手の本文も絡みの本文もログに出さない**（長さだけ）。⚠ オーナーへの下書きの DM は本文を含む（オーナーだけに届く）
  class TeaseWorker
    include Package

    FALLBACK_INTERVAL = 600
    # ⚠ 覚えておく試した投稿の数（古いほうから忘れる）。⚠ 対象は書かれて 15 分以内なので、巡回 10 分なら数件で足りる。
    SEEN_LIMIT = 1000
    DRAFT_HEADER = '〔絡みの下書き〕'.freeze

    # @param service [MastodonService, nil] ⚠ テストが差し替える
    # @param gate [TeaseGate, nil] ⚠ テストが差し替える
    # @param candidates [TeaseCandidates, nil] ⚠ テストが差し替える
    # @param model [ChatModel, nil] ⚠ テストが差し替える
    # @param sleeper [#call, nil] ⚠ テストが差し替える
    def initialize(service: nil, gate: nil, candidates: nil, model: nil, sleeper: nil)
      @service = service
      @gate = gate
      @candidates = candidates
      @model = model
      @sleeper = sleeper || ->(seconds) {sleep(seconds)}
      @stopping = false
      @seen = []
    end

    def self.enabled?
      return TeaseGate.enabled? && ChatModel.enabled?
    end

    # `hadlar status` に出す状態（→ `Heartbeat.touch`）。
    # @return [Symbol] :off / :draft / :on
    def self.mode
      return :off unless enabled?
      return Config.instance['/chat/tease/draft'] == false ? :on : :draft
    end

    attr_reader :thread

    def start
      return nil unless self.class.enabled?
      @thread ||= Thread.new do
        Thread.current.name = 'hadlar-tease'
        run
      end
      return @thread
    end

    # ⚠ **trap から呼ばれる**（Mutex を掴まない → `MentionListener#stop`）。
    def stop
      @stopping = true
      return nil unless @thread
      @thread.kill
      @thread.join(MentionListener::JOIN_TIMEOUT)
      return nil
    rescue ThreadError
      return nil
    end

    def run
      until @stopping
        patrol
        @sleeper.call(wait)
      end
    end

    # 1 回の巡回。⚠ **例外を上げない。**
    # @return [Symbol] 結果（ログと同じ）
    def patrol(now = Time.now)
      closed = gate.closed_reason(now)
      return log(:closed, reason: closed) if closed
      fresh = candidates.select(service.home_timeline).reject {|s| @seen.include?(s['id'].to_s)}
      status = gate.pick(fresh, now)
      return log(:none) unless status
      return tease(status, now)
    rescue => e
      logger.error(tease: 'patrol', error: e)
      report_error(e, tease: 'patrol')
      return :error
    end

    private

    # ⚠ **LLM を呼ぶ前に試行を数える**（落ちても費用はかかりうる・上限は試行で持つ）。
    # 🔴 **同じ投稿に 2 度 LLM を呼ばない**（相手ごとの間隔が対象の古さより短い設定でも）。⚠ `@seen` はプロセスの中の手前の歯止めで、
    # 再起動をまたぐのは門の記録（`chat_event.status_id`・`TeaseGate#pick`）。
    def tease(status, now)
      @seen.push(status['id'].to_s)
      @seen.shift while @seen.size > SEEN_LIMIT
      gate.record_try(status, now)
      reply = model.tease(ChatThread.text_of(status))
      return log(:failed, status_id: status['id']) unless reply
      return log(:silent, status_id: status['id']) if reply.silent?
      deliver(status, reply.text)
      gate.record_post(status, now)
      return log(draft? ? :drafted : :posted, status_id: status['id'], length: reply.text.length)
    end

    def deliver(status, text)
      return draft(status, text) if draft?
      account = status['account'] || {}
      service.post_status(
        "@#{account['acct']} #{ChatThread.unmention(text)}",
        visibility: 'unlisted',
        in_reply_to_id: status['id'],
        idempotency_key: "hadlar-tease-#{status['id']}",
      )
    end

    # 🔴🔴 **相手をメンションしない**（→ `ChatOwnerNotice#notify_owner`）。⚠ DM は本文でメンションした全員に届く。
    def draft(status, text)
      acct = status.dig('account', 'acct').to_s.delete_prefix('@')
      body = [
        "@#{config['/chat/owner']} #{DRAFT_HEADER}#{acct} への絡み（まだ投稿していない）",
        status['url'].to_s,
        ChatThread.unmention(text),
      ].join("\n")
      key = "hadlar-tease-draft-#{status['id']}"
      service.post_status(body, visibility: 'direct', idempotency_key: key)
    end

    def draft?
      return self.class.mode == :draft
    end

    def log(result, **fields)
      logger.info(tease: 'patrol', result: result, **fields)
      return result
    end

    def wait
      value = config['/chat/tease/interval']
      seconds = Fugit::Duration.parse(value.to_s)&.to_sec
      return seconds if seconds&.positive?
      logger.error(tease: 'patrol', message: 'bad interval', value: value.to_s)
      return FALLBACK_INTERVAL
    end

    def service
      @service ||= MastodonService.new
      return @service
    end

    def gate
      @gate ||= TeaseGate.new
      return @gate
    end

    def candidates
      @candidates ||= TeaseCandidates.new(own_id: service.account['id'])
      return @candidates
    end

    def model
      @model ||= ChatModel.new
      return @model
    end
  end
end
