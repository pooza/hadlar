module Hadlar
  # 自分から絡む候補の絞り込み（#35・設計は #25）。⚠ **LLM を呼ばない**（費用の歯止めの 1 段目）。
  # ⚠ **副作用なし** — 投稿も記録もしない。上限・抽選は門（#36）、LLM は #37 の役目。
  #
  # 🔴 **迷ったら落とす。**話しかけられていない場面なので、返事のとき以上に寄らない。
  #
  # - 🔴 **書き手はフォロワーだけ**（`FollowerRoster`）。⚠ **ホームはフォロワーと一致しない**（hadlar がフォローしている人と、
  #   そのブースト・返信が流れる）ので、ホームに出ていても必ず一覧で確かめる。⚠ 一覧が引けなければ落とす
  # - 🔴 **このサーバーの人だけ**（0.2・オーナー 2026-11-28）。⚠ `acct` に `@` があれば他サーバー
  # - 🔴 **返事を止めている相手は落とす**（`chat block`・ペナルティ・「絡むな」）→ `stopped`
  # - 🔴 **`public` だけ** — ⚠⚠ フォローを返しているので**相手のフォロワー限定の投稿もホームに来る**。返事の対応表の
  #   まま返すと「hadlar のフォロワー」という別の集合へ中身が出る。⚠ 未収載はホームにだけ流した投稿なので外す（0.2）
  # - 🔴 **CW・センシティブ・添付・投票・引用・URL・ハッシュタグ・他人へのメンションが付いたものは落とす**（0.2・オーナー）。
  #   ⚠ タグはその場（実況・企画）への割り込みになり、URL は時事の共有になりやすい
  # - ⚠ ブースト・返信は落とす（人が話しているところへ差し込まない）
  class TeaseCandidates
    include Package

    # 落とした理由（`tease preview` に出す）。⚠ 並びは判定の順。
    REASONS = [
      :own, :bot, :remote, :not_public, :reblog, :reply, :spoiler, :sensitive, :media, :poll,
      :quote, :mention, :tag, :url, :short, :long, :stale,
      :stopped, :followers_unknown, :not_follower
    ].freeze

    URL_PATTERN = %r{https?://}i

    # @param own_id [String] hadlar 自身のアカウント ID
    # @param followed_by [#call, nil] ID → フォロワーか（⚠ 引けなければ例外）。⚠ テストが差し替える
    # @param stopped [#call, nil] ID → 返事を止めている相手か。⚠ テストが差し替える
    # @param clock [#call, nil] ⚠ テストが差し替える
    def initialize(own_id:, followed_by: nil, stopped: nil, clock: nil)
      @own_id = own_id.to_s
      @followed_by = followed_by || ->(id) {FollowerRoster.instance.include?(id)}
      @stopped = stopped || ->(id) {default_stopped?(id)}
      @clock = clock || -> {Time.now}
    end

    # @param statuses [Array<Hash>] ホームの投稿（Mastodon の status）
    # @return [Array<Hash>] 通ったもの（並びはそのまま）
    def select(statuses)
      return statuses.select {|status| reason(status).nil?}
    end

    # 落とす理由。⚠ **通るなら nil。**⚠ 安い判定（投稿の中身）から先に見て、一覧・DB は最後に引く。
    # @return [Symbol, nil]
    def reason(status)
      return content_reason(status) || account_reason(status['account'] || {})
    end

    private

    def content_reason(status)
      return author_reason(status['account'] || {}) || shape_reason(status)
    end

    # 書き手の形（一覧・DB を引かずに分かるもの）。
    def author_reason(account)
      return :own if account['id'].to_s == @own_id
      return :bot if account['bot']
      return :remote if account['acct'].to_s.include?('@')
      return nil
    end

    def shape_reason(status)
      return :not_public unless status['visibility'] == 'public'
      return :reblog if status['reblog']
      return :reply if status['in_reply_to_id'] || status['in_reply_to_account_id']
      return :spoiler unless status['spoiler_text'].to_s.strip.empty?
      return :sensitive if status['sensitive']
      return attachment_reason(status) || text_reason(status)
    end

    def attachment_reason(status)
      return :media if Array(status['media_attachments']).any?
      return :poll if status['poll']
      return :quote if status['quote']
      return :mention if Array(status['mentions']).any?
      return :tag if Array(status['tags']).any?
      return nil
    end

    def text_reason(status)
      return :url if status['card'] || status['content'].to_s.match?(URL_PATTERN)
      length = ChatThread.text_of(status).length
      return :short if length < setting('min_length')
      return :long if length > setting('max_length')
      return :stale if stale?(status)
      return nil
    end

    def account_reason(account)
      id = account['id'].to_s
      return :stopped if @stopped.call(id)
      follower = follower_state(id)
      return :followers_unknown if follower.nil?
      return :not_follower unless follower
      return nil
    end

    # ⚠ **引けなければ nil**（フォロワーでない、とは答えない）。
    def follower_state(id)
      return @followed_by.call(id)
    rescue Ginseng::GatewayError, Ginseng::AuthError => e
      logger.warn(tease: 'candidates', message: 'followers unknown', error_class: e.class.name)
      return nil
    end

    # ⚠ 書かれた時刻が読めなければ古いものとして落とす。
    def stale?(status)
      created = Time.parse(status['created_at'].to_s)
      return @clock.call - created > max_age
    rescue ArgumentError, TypeError
      return true
    end

    def max_age
      value = setting('max_age')
      seconds = Fugit::Duration.parse(value.to_s)&.to_sec
      return seconds if seconds&.positive?
      raise Ginseng::ConfigError, "tease: bad candidate max_age '#{value}'"
    end

    # ⚠ `FollowSync#stopped?` の判定に、「絡むな」（#39）を足したもの。
    def default_stopped?(id)
      @repository ||= ChatRepository.new
      return true if @repository.blocked(id)
      return true if @repository.opted_out(id)
      return ChatGate.new(repository: @repository).penalized?(id)
    end

    def setting(key)
      return config["/chat/tease/candidate/#{key}"]
    end
  end
end
