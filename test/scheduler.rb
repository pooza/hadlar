module Hadlar
  class SchedulerTest < TestCase
    setup do
      Scheduler.instance.clear
    end

    teardown do
      Scheduler.instance.clear
      # ⚠ 単体テストの中で `every` を登録するので、外して次のテストに持ち越さない。
      Scheduler.instance.scheduler.jobs.each(&:unschedule)
    end

    # ⚠ hadlar は投稿の枠（makoto2 の `PostingJob`）を持たないので、`exec` に応える偽物で登録の口だけを見る。
    # 偽物は tick のたびに `source` を呼ぶ（枠の頭の判定は持たない）。
    FakeJob = Struct.new(:name, :source) do
      def timetable
        return 'fake'
      end

      def exec(time = nil)
        return source.call(time)
      end
    end

    def job(name, source)
      return FakeJob.new(name, source)
    end

    def jst(hour, minute = 0)
      return Time.new(2026, 11, 4, hour, minute, 0, '+09:00')
    end

    def test_register
      assert_equal(Scheduler.instance, Scheduler.instance.register(job('live', proc {'ok'})))
    end

    def test_tick_runs_registered_jobs
      calls = []
      Scheduler.instance.register(job('live', proc {|slot| calls.push(slot) && nil}))
      Scheduler.instance.tick(jst(12, 0))
      Scheduler.instance.tick(jst(12, 1))

      assert_equal(2, calls.size)
    end

    # ⚠⚠ **1 本の投稿が落ちても他を巻き込まない。**ライブ当日に 1 本の例外で
    # 残りの枠を全部落とすのが最悪の壊れ方。
    def test_tick_isolates_failures
      reached = []
      exploding = job('exploding', proc {'ok'})
      exploding.define_singleton_method(:exec) {|_time = nil| raise 'boom'}
      Scheduler.instance.register(exploding)
      Scheduler.instance.register(job('live', proc {reached.push(:live) && nil}))

      assert_nothing_raised {Scheduler.instance.tick(jst(12, 0))}
      assert_equal([:live], reached)
    end

    def test_tick_without_jobs
      assert_equal([], Scheduler.instance.tick(jst(12, 0)))
    end

    # 🔴 **tick が回ったこと自体を痕跡に残す**（makoto2#80 の黄 7）。⚠⚠ **ハートビートは別の
    # rufus ジョブ**なので、⚠ **tick 側だけが詰まっても `at` は更新され続ける。**
    def test_tick_records_its_own_trace
      FileUtils.rm_f(Heartbeat.path)
      Scheduler.instance.tick(jst(12, 0))

      assert_not_nil(Heartbeat.ticked_at)
      assert_false(Heartbeat.tick_stale?)
    ensure
      FileUtils.rm_f(Heartbeat.path)
    end

    # ⚠ **投稿が 1 本も出ない枠でも記録する。**見たいのは**枠を見に行けているか**で
    # あって、投稿の成否は別の痕跡が持つ。
    def test_tick_records_its_trace_even_without_a_post
      FileUtils.rm_f(Heartbeat.path)
      Scheduler.instance.register(job('live', proc {}))
      Scheduler.instance.tick(jst(13, 13))

      assert_not_nil(Heartbeat.ticked_at)
    ensure
      FileUtils.rm_f(Heartbeat.path)
    end

    # ⚠⚠ **痕跡が書けなくても tick は止めない**（痕跡は観測のためのもの）。
    def test_a_broken_trace_does_not_stop_the_tick
      calls = []
      Scheduler.instance.register(job('live', proc {|slot| calls.push(slot) && nil}))
      # ⚠ **元のメソッドを持って戻す。**`record_tick` は `class << self` の中に居るので、
      # ⚠⚠ **`remove_method` では復元ではなく削除になる**（後続のテストが巻き添えになる）。
      original = Heartbeat.method(:record_tick)
      Heartbeat.define_singleton_method(:record_tick) {|**| raise 'boom'}

      assert_nothing_raised {Scheduler.instance.tick(jst(12, 0))}
      assert_equal(1, calls.size)
    ensure
      Heartbeat.define_singleton_method(:record_tick, original)
    end

    # ⚠⚠ **常駐の開始直後に 1 回叩くこと。**`every` は最初の間隔を待つので、これが
    # 無いと**枠の頭 ＋ tolerance の内側で再起動した枠が落ちる**（→ makoto2#47）。
    # ⚠ ここでは**登録の仕方**（起動直後に叩くか）だけを見る。
    def test_schedule_posts_ticks_immediately
      calls = []
      recording = job('live', proc {'ok'})
      recording.define_singleton_method(:exec) {|_time = nil| calls.push(:exec) && nil}
      Scheduler.instance.register(recording)

      Scheduler.instance.send(:schedule_posts)

      assert_equal([:exec], calls)
    end

    # ⚠⚠ **登録が先、初回の tick が後。**初回の tick は投稿を伴うので、HTTP の再送で
    # 秒単位に伸びうる。⚠ **逆順だと、伸びている間に次の枠が tolerance ごと過ぎて
    # 落ちる**（ライブの枠は 2 分間隔）。
    def test_schedule_posts_registers_before_the_first_tick
      registered = []
      recording = job('live', proc {'ok'})
      recording.define_singleton_method(:exec) do |_time = nil|
        registered.push(Scheduler.instance.scheduler.jobs.size)
        next nil
      end
      Scheduler.instance.register(recording)

      Scheduler.instance.send(:schedule_posts)

      # 初回の tick が走った時点で、繰り返しの登録が既に済んでいること。
      assert_equal([1], registered)
    end

    # 🔴 **登録が 1 つも無くても tick を回す**（hadlar）。⚠⚠ tick は別スレッドの見張りも兼ねる（makoto2#611）。
    # ⚠ makoto2 は「登録が無ければ tick を作らない」だった。
    def test_schedule_posts_without_jobs
      assert_equal(0, Scheduler.instance.send(:schedule_posts))
      assert_equal(1, Scheduler.instance.scheduler.jobs.size)
    end

    # 🔴 **死んだ別スレッドの名前を tick が痕跡に書く**（makoto2#611）。⚠ 起こしていない（nil）ものは数えない。
    def test_dead_threads_are_recorded_on_tick
      FileUtils.rm_f(Heartbeat.path)
      dead = Thread.new {nil}.tap(&:join)
      alive = Thread.new {sleep}
      subject = Scheduler.instance

      assert_nil(subject.dead_threads)
      subject.thread_watch = -> {{'hadlar-chat' => dead, 'hadlar-stream' => alive, 'hadlar-follow' => nil}}

      assert_equal(['hadlar-chat'], subject.dead_threads)
      subject.tick

      assert_equal(['hadlar-chat'], Heartbeat.dead_threads)
    ensure
      alive&.kill
      FileUtils.rm_f(Heartbeat.path)
    end

    # 🔴 **新しく死んだスレッドは 1 回だけ Sentry へ**（makoto2#639）。⚠ 次の tick では送らない。
    def test_a_newly_dead_thread_is_reported_once
      FileUtils.rm_f(Heartbeat.path)
      dead = Thread.new {nil}.tap(&:join)
      subject = Scheduler.instance
      reported = []
      subject.define_singleton_method(:report_error) {|error, **| reported.push(error.message)}
      subject.thread_watch = -> {{'hadlar-chat' => dead}}
      2.times {subject.tick}

      assert_equal(['thread hadlar-chat is dead'], reported)
    ensure
      subject.singleton_class.remove_method(:report_error)
      FileUtils.rm_f(Heartbeat.path)
    end
  end
end
