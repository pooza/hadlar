module Hadlar
  class TeaseCandidatesTest < TestCase
    NOW = Time.utc(2026, 11, 28, 3, 0, 0)

    def setup
      @followers = ['10', '11']
      @stopped = []
      @subject = subject
    end

    def subject(followed_by: nil)
      return TeaseCandidates.new(
        own_id: '1',
        followed_by: followed_by || ->(id) {@followers.include?(id)},
        stopped: ->(id) {@stopped.include?(id)},
        clock: -> {NOW},
        ignore_tags: ['Default'],
      )
    end

    def status(**overrides)
      account = {'id' => '10', 'acct' => 'alice', 'bot' => false}.merge(overrides.delete(:account) || {})
      return {
        'id' => '100',
        'account' => account,
        'visibility' => 'public',
        'created_at' => (NOW - 60).iso8601,
        'content' => '<p>今日はいい天気だから散歩に行こうと思う</p>',
        'spoiler_text' => '',
        'sensitive' => false,
        'media_attachments' => [],
        'mentions' => [],
        'tags' => [],
        'reblog' => nil,
        'in_reply_to_id' => nil,
        'in_reply_to_account_id' => nil,
        'poll' => nil,
        'card' => nil,
      }.merge(overrides.transform_keys(&:to_s))
    end

    def test_a_plain_public_post_by_a_local_follower_passes
      assert_nil(@subject.reason(status))
      assert_equal(['100'], @subject.select([status, status(id: '101', visibility: 'unlisted')]).map {|s| s['id']})
    end

    # 🔴 **フォロワーだけ・このサーバーの人だけ**（#25・オーナー）。
    def test_followers_on_this_server_only
      assert_equal(:not_follower, @subject.reason(status(account: {'id' => '99'})))
      assert_equal(:remote, @subject.reason(status(account: {'acct' => 'bob@example.com'})))
      assert_equal(:own, @subject.reason(status(account: {'id' => '1'})))
      assert_equal(:bot, @subject.reason(status(account: {'bot' => true})))
    end

    # 🔴 **一覧が引けなければ落とす**（空の一覧で「絡んでよい」と答えない）。
    def test_unknown_followers_are_dropped
      failing = subject(followed_by: ->(_id) {raise Ginseng::GatewayError, 'followers: not loaded yet'})

      assert_equal(:followers_unknown, failing.reason(status))
    end

    # 🔴 **返事を止めている相手（block・ペナルティ・絡むな）には絡まない。**
    def test_stopped_accounts_are_dropped
      @stopped.push('10')

      assert_equal(:stopped, @subject.reason(status))
    end

    # 🔴 **既定の判定は block・ペナルティ・「絡むな」を見る**（#39）。
    def test_the_default_stop_includes_opt_outs
      repository = ChatRepository.new(empty_db)
      subject = TeaseCandidates.new(own_id: '1', followed_by: ->(_id) {true}, clock: -> {NOW})
      subject.instance_variable_set(:@repository, repository)

      assert_nil(subject.reason(status))
      repository.opt_out('10', 'alice')

      assert_equal(:stopped, subject.reason(status))
    end

    # 🔴 **`public` だけ** — フォロワー限定はホームに来ても、中身を別の集合へ出さない。
    def test_only_public_posts
      ['unlisted', 'private', 'direct'].each do |visibility|
        assert_equal(:not_public, @subject.reason(status(visibility:)))
      end
    end

    # 🔴 **CW・タグ・URL・画像などは 0.2 では絡まない**（オーナー 2026-11-28）。
    def test_posts_with_extras_are_dropped
      {
        reblog: [{reblog: {'id' => '5'}}],
        reply: [{in_reply_to_id: '5'}, {in_reply_to_account_id: '10'}],
        spoiler: [{spoiler_text: 'ネタバレ'}],
        sensitive: [{sensitive: true}],
        media: [{media_attachments: [{'id' => '1'}]}],
        poll: [{poll: {'id' => '1'}}],
        quote: [{quote: {'id' => '1'}}],
        mention: [{mentions: [{'id' => '11'}]}],
        tag: [{tags: [{'name' => 'jikkyo'}]}, {tags: [{'name' => 'default'}, {'name' => 'jikkyo'}]}],
        url: [{card: {'url' => 'https://example.com'}}, {content: '<p>見てこれ https://example.com/a すごい</p>'}],
      }.each do |reason, cases|
        cases.each {|fields| assert_equal(reason, @subject.reason(status(**fields)), fields.inspect)}
      end
    end

    # 🔴 **サーバーが毎回付ける既定のタグは数えない**（オーナー 2026-11-28）。⚠ 数えると公開の投稿がすべて落ちる。
    def test_default_tags_are_ignored
      assert_nil(@subject.reason(status(tags: [{'name' => 'default'}])))
      assert_nil(@subject.reason(status(tags: [{'name' => 'DEFAULT'}])))
    end

    def test_length_and_age
      assert_equal(:short, @subject.reason(status(content: '<p>ねむい</p>')))
      assert_equal(:long, @subject.reason(status(content: "<p>#{'あ' * 301}</p>")))
      assert_equal(:stale, @subject.reason(status(created_at: (NOW - (16 * 60)).iso8601)))
      assert_equal(:stale, @subject.reason(status(created_at: 'not a time')))
    end

    # ⚠ **安い判定から先に見る** — 中身で落ちる投稿のために一覧を引かない。
    def test_content_is_checked_before_the_roster
      calls = 0
      counting = subject(followed_by: ->(_id) {(calls += 1) && true})
      counting.reason(status(visibility: 'private'))

      assert_equal(0, calls)
    end
  end
end
