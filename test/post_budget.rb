module Hadlar
  # 投稿先が数える本文の長さ（makoto2#282）。
  class PostBudgetTest < TestCase
    def budget
      return PostBudget.new
    end

    # 🔴 **URL は長さによらず 23 字**（投稿先と同じ数え方）。
    def test_a_url_counts_as_a_fixed_length
      text = "あいう https://example.com/#{'x' * 100} えお"

      assert_equal(3 + 1 + 23 + 1 + 2, PostBudget.length(text))
    end

    # ⚠⚠ **見た目の 1 文字を 1 字と数える**（Codex の P2）。🔴 **家族の絵文字は 7 コードポイントで 1 字。**
    def test_a_grapheme_cluster_counts_as_one
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

      assert_equal(1, PostBudget.length(family))
      assert_equal(2, PostBudget.length("が\u{3099}#{family}".unicode_normalize(:nfd)))
    end

    # 🔴 **TLD を持たないホストは URL と数えない**（makoto2#351）。⚠⚠ **投稿先はそれを素の長さで数える**
    # ので、23 字に畳むと短く見積もる。
    def test_a_host_without_a_tld_is_not_a_url
      ip = "http://192.168.1.10:9292/#{'x' * 40}"

      assert_equal(ip.length, PostBudget.length(ip))
      assert_equal(17, PostBudget.length('http://localhost/'))
      # ⚠ **英字の TLD でも、実在しなければ URL ではない**（Codex の P2）。
      assert_equal(26, PostBudget.length('https://foo.local/abcdefgh'))
      assert_equal(23, PostBudget.length("https://music.apple.com/jp/album/#{'x' * 40}"))
    end

    # 🔴 **申告のほうが短いときだけずれと言う**（makoto2#351）。⚠ **申告が無ければ判定しない。**
    def test_limit_mismatch
      limit = budget.limit

      assert_nil(budget.limit_mismatch(limit))
      assert_nil(budget.limit_mismatch(limit + 1))
      assert_nil(budget.limit_mismatch(nil))
      assert_include(budget.limit_mismatch(limit - 1), (limit - 1).to_s)
    end

    # ⚠⚠ **前方一致する URL を長く数えない**（Codex の P2）。
    def test_urls_sharing_a_prefix_count_as_23_each
      assert_equal(23 + 1 + 23, PostBudget.length('https://x.example.com/a https://x.example.com/a/b'))
    end

    # 🔴 **URL の末尾の句読点は URL の外で数える**（makoto2#424）。⚠⚠ **期待値は Mastodon の
    # initializer を読み込んだ twitter-text 3.1.0 の実測**（`StatusLengthValidator` と同じ数え方）。
    def test_trailing_punctuation_is_not_part_of_the_url
      {
        'https://example.com/a.' => 24,
        'https://example.com/a!' => 24,
        'https://example.com/a;' => 24,
        'https://example.com/a~' => 24,
        'https://example.com/a=' => 24,
        'https://example.com/a:' => 24,
        'https://example.com/a,' => 24,
        'https://example.com/a?' => 24,
        'https://example.com/a&' => 24,
        'https://example.com/a*' => 24,
        "https://example.com/a'" => 24,
        'https://example.com.' => 24,
        'https://example.com/a...' => 26,
        'https://example.com/a)' => 24,
        '(https://example.com/a)' => 25,
        '見て https://example.com/a. 次' => 29,
      }.each do |text, length|
        assert_equal(length, PostBudget.length(text), text)
      end
    end

    # ⚠ **URL の中で終わってよい形は削らない**（makoto2#424）。⚠⚠ **クエリの末尾は path と規則が違う**
    # （`=` / `&` で終わってよい）。**釣り合った括弧も URL の一部。**
    def test_url_endings_that_stay_in_the_url
      [
        'https://example.com/a/',
        'https://example.com/a#b',
        'https://example.com/a?b=',
        'https://example.com/a?b=1&',
        'https://example.com/a-',
        'https://ja.wikipedia.org/wiki/Foo_(bar)',
        'https://music.apple.com/jp/album/x/123?i=456',
      ].each do |text|
        assert_equal(23, PostBudget.length(text), text)
      end
      assert_equal(24, PostBudget.length('https://example.com/a?b=1.'))
      assert_equal(24, PostBudget.length('https://ja.wikipedia.org/wiki/Foo_(bar).'))
    end

    # 🔴 **投稿先と同じ長さで数える形**（makoto2#443）。⚠⚠ **期待値は Mastodon の initializer を読み込んだ
    # twitter-text 3.1.0 の実測**（`StatusLengthValidator` と同じ置換）。⚠ **前半は makoto2#443 の表・
    # 後半は同じ突き合わせ（46,000 通りの生成）で見つかった形。**⚠ **makoto2#443 の時点で短く数えていた形と、
    # そこで直したときに長く数えかけた形（`https://a.com-` など）が混ざる**ので、名前は向きを言わない（makoto2#462）。
    def test_url_shapes_counted_as_the_destination_does
      {
        'https://example.com/a(b' => 25,
        'https://example.com/a()' => 25,
        'https://example.com/a(((b)))' => 30,
        "https://example.music/#{'a' * 44}" => 66,
        'https://user@example.com/aaaaaaaaaaaaaaaaa' => 42,
        "xhttps://example.com/#{'a' * 29}" => 50,
        'https://-foo.example.com/a' => 26,
        'gemini://a.io' => 23,
        'https://co.uk' => 23,
        "https://example.com.#{'a' * 30}" => 54,
        'https://a.com.io+x' => 28,
        # ⚠ **TLD の直後の `-` では戻らない**（PR makoto2#458 の Codex の P2 への実測 — 投稿先も素の長さ）。
        'https://a.com-' => 14,
        'https://a.com-foo/bar' => 21,
        # 🔴 **長すぎる t.co の slug と、唯一の TLD の直後の `+`**（PR makoto2#458 の Codex の P2 ×2 — 投稿先は素の長さ）。
        "https://t.co/#{'a' * 41}" => 54,
        "https://t.co/#{'a' * 40}" => 23,
        'https://abcdefghijklmnop.com+x' => 30,
        'https://a.com+x' => 15,
        'https://a.io#frag' => 28,
        'https://a.io/~?b=' => 27,
        'https://t.co/abc/def' => 27,
        "https://example.com/#{'a' * 4100}" => 4120,
      }.each do |text, length|
        assert_equal(length, PostBudget.length(text), text)
      end
      assert_equal(23, PostBudget.length('https://example.com/a(b(c)d)e'))
    end

    # 🔴 **投稿先より短く数えない 3 系統**（makoto2#461）。⚠⚠ **期待値は同じ oracle**（Mastodon の initializer ＋
    # twitter-text 3.1.0）の実測。
    def test_shapes_found_after_the_release_review
      {
        # ⚠ **URL を切った後・認めなかった後から探し直す**（`gsub` は飲んだ後ろを探さなかった）。
        'https://a.com.https://b.com' => 47,
        'https://https://b.com' => 31,
        'http://a.jp/x(http://b.jp/y(http://c.jp' => 71,
        # ⚠ **非 ASCII のホスト**（IDN・Unicode の TLD）。
        'https://例え.jp' => 23,
        'https://プリキュア.com' => 23,
        'https://例え.コム' => 23,
        # ⚠ **port の後の `@`**。
        'https://a.com:80@b.com' => 29,
      }.each do |text, length|
        assert_equal(length, PostBudget.length(text), text)
      end
      assert_equal((10 * 23) + 9, PostBudget.length(Array.new(10, 'https://a.jp').join('.')))
    end

    # 🔴 **TLD は twitter-text の表で判定する**（makoto2#461）。⚠⚠ **Public Suffix List とは両方向にずれる** —
    # **`.za` は PSL に単独の規則が無いが投稿先は URL**、**`.music` は PSL にあるが投稿先は素の長さ。**
    def test_tlds_follow_twitter_text
      assert_equal(23, PostBudget.length('https://a.za'))
      assert_equal(23, PostBudget.length("https://a.za/#{'x' * 40}"))
      assert_equal(15, PostBudget.length('https://a.music'))
    end

    # ⚠⚠ **非 ASCII のホストは、23 字と素の長さの長いほう**（makoto2#461）。🔴 **投稿先は libidn に通して
    # 失敗すれば URL と認めない**が、その判定はこちらで再現できないので、短く数えない側に倒す。
    def test_a_non_ascii_host_counts_the_longer
      url = "https://例え.jp/#{'x' * 40}"

      assert_equal(url.length, PostBudget.length(url))
    end

    # ⚠ **ラベルが 63 字を超えるホストは URL ではない**（投稿先の IDN 変換が失敗する）。
    def test_a_too_long_label_is_not_a_url
      url = "https://#{'a' * 64}.com"

      assert_equal(url.length, PostBudget.length(url))
    end

    # 🔴 **入れ子のスキームは名指ししない**（PR makoto2#472 の Codex の P2）。
    def test_unfolded_urls_skip_schemes_nested_in_a_url
      assert_empty(PostBudget.unfolded_urls('https://a.com/?url=https://b.com/foo'))
      assert_equal(['https://a.music/?u=https://b.com'], PostBudget.unfolded_urls('https://a.music/?u=https://b.com'))
      assert_equal(['http://192.168.1.1/'], PostBudget.unfolded_urls('https://a.com/ http://192.168.1.1/'))
    end
  end
end
