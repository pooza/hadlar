module Hadlar
  class TeaseGateTest < TestCase
    # ⚠ 決まった値を順に返す乱数（`rand` は確率の抽選、`rand(n)` は人の抽選）。
    class FixedRandom
      def initialize(*values)
        @values = values
      end

      def rand(max = nil)
        value = @values.shift
        return max ? value % max : value
      end
    end

    # ⚠ **`setup` メソッドではなくコールバックで開ける** — メソッドは `TestCase` のコールバック（`quiet_chat`）より先に走り、
    # 開けた設定が上書きされる。
    setup do
      @repository = ChatRepository.new(empty_db)
      config['/chat/enabled'] = true
      config['/chat/tease/enabled'] = true
    end

    def now
      return Time.new(2026, 11, 28, 12, 0, 0, '+09:00')
    end

    def gate(*values)
      return TeaseGate.new(repository: @repository, random: FixedRandom.new(*values))
    end

    def status(id, account_id)
      return {'id' => id.to_s, 'account' => {'id' => account_id.to_s, 'acct' => "user#{account_id}"}}
    end

    def record(kind, account_id, at)
      @repository.record(account_id.to_s, "user#{account_id}", kind, at)
    end

    def test_it_is_open_when_enabled
      assert_nil(gate.closed_reason(now))
    end

    # 🔴 **既定は閉じている**（0.2 を当てただけでは絡み始めない）。⚠ 返事ごと止めたときも閉じる。
    def test_it_is_closed_by_default_and_with_chat_disabled
      config.reload
      quiet_chat
      config['/chat/enabled'] = true

      assert_false(config['/chat/tease/enabled'])
      assert_equal(:disabled, gate.closed_reason(now))

      config['/chat/tease/enabled'] = true
      config['/chat/enabled'] = false

      assert_equal(:disabled, gate.closed_reason(now))
    end

    # 🔴 **上限は試行（LLM を呼んだ回数）で数える**（空の返事も 1 回）。
    def test_the_daily_try_limit
      config['/chat/tease/limit/try_per_day'].times {|i| record(:tease_try, i, now - 3600)}

      assert_equal(:try_limit, gate.closed_reason(now))
      assert_nil(gate.closed_reason(now + TeaseGate::DAY))
    end

    def test_the_post_limit_and_interval
      record(:tease, 1, now - 60)

      assert_equal(:post_interval, gate.closed_reason(now))
      assert_nil(gate.closed_reason(now + (2 * 3600) + 1))

      config['/chat/tease/limit/post_per_day'] = 1

      assert_equal(:post_limit, gate.closed_reason(now + (3 * 3600)))
    end

    # ⚠ **抽選に外れたら LLM を呼ばない**（nil）。
    def test_the_chance
      config['/chat/tease/chance'] = 0.2

      assert_nil(gate(0.5).pick([status(1, 10)], now))
      assert_equal('1', gate(0.1, 0).pick([status(1, 10)], now)['id'])
      assert_nil(gate(0.0).pick([], now))
    end

    # ⚠ **まず人を一様に選び、その人の最新の 1 件**（多く書く人に偏らせない）。
    def test_it_picks_a_person_then_their_newest_post
      statuses = [status(1, 10), status(3, 10), status(2, 10), status(4, 11)]

      assert_equal('3', gate(0.0, 0).pick(statuses, now)['id'])
      assert_equal('4', gate(0.0, 1).pick(statuses, now)['id'])
    end

    # ⚠ **同じ相手には、試行は 1 日に 1 回・投稿は 3 日に 1 回。**
    def test_resting_accounts_are_skipped
      record(:tease_try, 10, now - 3600)

      assert_nil(gate(0.0, 0).pick([status(1, 10)], now))
      assert_equal('2', gate(0.0, 0).pick([status(1, 10), status(2, 11)], now)['id'])

      record(:tease, 11, now - (2 * TeaseGate::DAY))

      assert_nil(gate(0.0, 0).pick([status(2, 11)], now))
      assert_equal('2', gate(0.0, 0).pick([status(2, 11)], now + TeaseGate::DAY + 1)['id'])
    end

    def test_records
      gate.record_try(status(1, 10), now)
      gate.record_post(status(1, 10), now)

      assert_equal(1, @repository.count(:tease_try, now - 60, account_id: '10'))
      assert_equal(1, @repository.count(:tease, now - 60, account_id: '10'))
    end

    def test_a_bad_chance_is_a_config_error
      config['/chat/tease/chance'] = 2

      assert_raise(Ginseng::ConfigError) {gate(0.0).pick([status(1, 10)], now)}
    end
  end
end
