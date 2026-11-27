module Hadlar
  class TeaseWorkerTest < TestCase
    FakeService = Struct.new(:timeline, :posts) do
      def home_timeline = timeline

      def post_status(text, **)
        posts.push({text:, **})
      end
    end

    FakeGate = Struct.new(:closed, :picked, :tries, :posts) do
      def closed_reason(_now) = closed
      def pick(statuses, _now) = picked && statuses.find {|s| s['id'] == picked}
      def record_try(status, _now) = tries.push(status['id'])
      def record_post(status, _now) = posts.push(status['id'])
    end

    FakeCandidates = Struct.new(:dummy) do
      def select(statuses) = statuses
    end

    FakeModel = Struct.new(:reply, :texts) do
      def tease(text)
        texts.push(text)
        return reply
      end
    end

    setup do
      config['/chat/enabled'] = true
      config['/chat/tease/enabled'] = true
      config['/chat/tease/draft'] = false
      config['/anthropic/api_key'] = 'sk-test'
      @status = {
        'id' => '100', 'url' => 'https://example.com/@alice/100',
        'account' => {'id' => '10', 'acct' => 'alice'}, 'content' => '<p>散歩に行ってきた @bob</p>'
      }
      @service = FakeService.new([@status], [])
      @gate = FakeGate.new(nil, '100', [], [])
      @model = FakeModel.new(reply('フン、呑気なものよ。@bob に伝えておけ'), [])
    end

    def reply(text)
      return ChatModel::Reply.new(text:, marks: [], usage: {})
    end

    def worker
      return TeaseWorker.new(service: @service, gate: @gate, candidates: FakeCandidates.new, model: @model)
    end

    # 🔴 **`unlisted` で、相手にだけ宛てて、本文の `@` はメンションにしない。**⚠ 同じ投稿に 2 度絡まない（冪等キー）。
    def test_it_posts_a_tease
      assert_equal(:posted, worker.patrol)
      post = @service.posts.first

      assert_equal('unlisted', post[:visibility])
      assert_equal('100', post[:in_reply_to_id])
      assert_equal('hadlar-tease-100', post[:idempotency_key])
      assert_match(/\A@alice /, post[:text])
      assert_no_match(/(?<![\p{L}\p{N}])@bob/, post[:text].delete_prefix('@alice '))
      assert_equal(['散歩に行ってきた @bob'], @model.texts)
      assert_equal(['100'], @gate.tries)
      assert_equal(['100'], @gate.posts)
    end

    # 🔴 **下書きモードはオーナーへ DM**。🔴🔴 **相手をメンションしない**（DM は本文でメンションした全員に届く）。
    def test_draft_mode_sends_the_owner_a_dm
      config['/chat/tease/draft'] = true

      assert_equal(:draft, TeaseWorker.mode)
      assert_equal(:drafted, worker.patrol)
      post = @service.posts.first

      assert_equal('direct', post[:visibility])
      assert_match(/\A@pooza /, post[:text])
      # ⚠ URL の中の `/@alice/` はメンションにならない。
      assert_no_match(%r{(?<![\p{L}\p{N}/])@alice}, post[:text].delete_prefix('@pooza '))
      assert_includes(post[:text], 'https://example.com/@alice/100')
      assert_nil(post[:in_reply_to_id])
      assert_equal(['100'], @gate.posts)
    end

    # ⚠ **空の返事 ＝ 絡まない**（試行には数え、投稿には数えない）。
    def test_silence_is_counted_as_a_try_only
      @model.reply = reply('')

      assert_equal(:silent, worker.patrol)
      assert_empty(@service.posts)
      assert_equal(['100'], @gate.tries)
      assert_empty(@gate.posts)
    end

    def test_closed_or_nothing_picked_does_not_call_the_model
      @gate.closed = :try_limit

      assert_equal(:closed, worker.patrol)
      @gate.closed = nil
      @gate.picked = nil

      assert_equal(:none, worker.patrol)
      assert_empty(@model.texts)
      assert_empty(@gate.tries)
    end

    def test_a_failed_model_posts_nothing
      @model.reply = nil

      assert_equal(:failed, worker.patrol)
      assert_empty(@service.posts)
    end

    # 🔴 **巡回が落ちてもスレッドを死なせない**（makoto2#611）。
    def test_errors_do_not_escape
      def @service.home_timeline = raise(Ginseng::GatewayError, 'mastodon returned 503')

      assert_equal(:error, worker.patrol)
    end

    # 🔴 **既定は閉じている**（起こさない）。
    def test_it_is_off_by_default
      config.reload
      quiet_chat

      assert_equal(:off, TeaseWorker.mode)
      assert_nil(TeaseWorker.new.start)
    end
  end
end
