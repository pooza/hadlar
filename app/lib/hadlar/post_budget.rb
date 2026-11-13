require 'yaml'

module Hadlar
  # 投稿先が数える本文の長さ（makoto2#282 から写した）。
  #
  # ⚠ makoto2 では原稿の取り込みで上限を超える原稿を弾くのに使っていた（朝挨拶・曲紹介・ライブの台本の予算）。
  # hadlar は原稿を持たないので、長さの数え方（`length`）と、投稿先の申告との突き合わせ（`limit_mismatch`）だけを残した。
  #
  # ⚠ **URL は投稿先と同じ規則で数える**（`holiday` は素の長さ 576 字だが実効 328 字）。🔴 **原則は 23 字**だが、
  # **投稿先が URL と認めない形（`.music` の TLD など）は素の長さ・非 ASCII のホストは長いほう**（→ `url_length`・makoto2#483）。
  #
  # ⚠⚠ **空白も改行も挟まない長い連なりに ASCII の `.` があると、長さの二乗で重くなる**（投稿先の正規表現と
  # 同じ構造なので同じだけ重い）。🔴 **句読点だけで続く和文 3000 字の末尾に URL を足すと 1.7 秒**（v0.8.0 の
  # リリース前レビューで実測）。⚠ **スキームが 1 つも無い本文は走査しない**（→ `fold`）ので、URL の無い原稿は
  # 連なりが長くても速い。⚠ **改行で区切られた実際の原稿（makoto-scripts の 2,222 文字列）は合計 0.03 秒。**
  class PostBudget
    include Package

    # 🔴 **Mastodon は URL の長さによらず 23 字と数える。**
    URL_LENGTH = 23

    # ⚠ **畳んだ URL の形**（中身は数えるだけなので何でもよい）。
    FOLDED = ('x' * URL_LENGTH).freeze

    # ⚠ **`ValidateError` の文面に出す URL の長さ**（→ `unfolded_urls`）。
    NOTE_URL_LENGTH = 40

    # ⚠ **これより長い URL を投稿先は URL と認めない**（twitter-text の `MAX_URL_LENGTH`）。
    MAX_URL_LENGTH = 4096

    # ⚠ **t.co は英数字の slug までしか URL にしない**（twitter-text の `valid_tco_url`）。
    TCO_PATTERN = %r{\Ahttps?://t\.co/([a-z0-9]+)}i
    MAX_TCO_SLUG_LENGTH = 40

    # ⚠ **ラベルがこれより長いと、投稿先の IDN 変換（libidn の `toASCII`）が失敗し、URL と認めない。**
    MAX_LABEL_LENGTH = 63

    # 投稿先が数える長さ。
    #
    # ⚠⚠ **書記素クラスタで数える**（Codex の P2）。🔴 **Mastodon は URL を置き換えたあと、見た目の
    # 1 文字（結合文字・ZWJ の絵文字）を 1 字と数える** — ⚠ **`String#length` はコードポイント
    # なので、家族の絵文字 1 つが数字ぶん長く出て、上限の近くで通る原稿を弾いてしまう。**
    #
    # 🔴 **URL の見つけ方は投稿先の写し**（makoto2#461）— ⚠⚠ **Mastodon は twitter-text 3.1.0 の
    # `extract_urls_with_indices` を、`valid_url` を上書きして使う**（`StatusLengthValidator`）。
    # **RFC 2396 の正規表現で拾ってから削る形（makoto2#443 まで）は、削った後ろを探し直さず、
    # 非 ASCII のホストを拾えず、短く数える形が 3 系統残っていた**（makoto2#461）。
    # ⚠ **同じ構造の正規表現で同じように走査する**（→ `VALID_URL`）。
    #
    # ⚠⚠ **弾きすぎる向きのずれは許すが、通しすぎる向きは許さない。**🔴 **投稿先と同じに決めきれない
    # 形は長いほうで数える**（→ `url_length`）。⚠ **メンションの `@user@host` を `@user` と数える
    # 置き換えは写していない**（写さなければ長く数えるだけ）。
    def self.length(text)
      return fold(text.to_s).first.grapheme_clusters.size
    end

    # ⚠ **23 字に畳まなかった URL**（makoto2#462）— 🔴 **投稿先が URL と認めない形**（`.music` の TLD・
    # 素の IP・長すぎるラベル）と、**非 ASCII のホストで素の長さのほうが長かったもの。**
    # ⚠ **スキームの付いた語を拾う**（URL と認められなかった語も、書いた人には URL に見えている）。
    # ⚠ **表示用に `NOTE_URL_LENGTH` 字で切る。**
    #
    # 🔴 **URL の中に入れ子になったスキームは拾わない**（PR makoto2#472 の Codex の P2）— ⚠⚠ **`https://a.com/?url=
    # https://b.com/` は外側ごと 23 字に畳まれている**ので、**中の `https://` を名指しすると嘘になる。**
    # ⚠ **素の長さで数えた URL の中も同じ**（外側を 1 本として名指しすれば足りる）。
    def self.unfolded_urls(text)
      text = text.to_s
      spans = fold(text).last
      return text.to_enum(:scan, SCHEME_START).filter_map do
        start = Regexp.last_match.begin(0)
        span = spans.find {|range, _| range.cover?(start)}
        next if span && (span.last || span.first.begin != start)
        word = text[start..][/\A\S+/]
        word.length > NOTE_URL_LENGTH ? "#{word[0, NOTE_URL_LENGTH]}…" : word
      end
    end

    # URL を畳んだ本文と、URL と数えた範囲（`[範囲, 23 字に畳んだか]` の列）。
    #
    # ⚠ **スキームが 1 つも無ければ走査しない**（v0.8.0 のリリース前レビュー）。🔴 **スキームの無い照合は
    # `url_span` がすべて捨てる**ので結果は同じ — **`ver.2` を含む長い和文で 1 秒余りかかっていた。**
    def self.fold(text)
      return text.dup, [] unless text.match?(SCHEME_START)
      counted = +''
      spans = []
      last = 0
      text.scan(VALID_URL) do
        matched = Regexp.last_match
        next unless (span = url_span(matched))
        start, finish = span
        value = url_length(text[start...finish], matched[:domain])
        spans.push([start...finish, value == FOLDED])
        counted << text[last...start] << value
        last = finish
      end
      return counted << text[last..], spans
    end

    # 投稿先が URL と数える範囲（文字位置）。⚠ **数えなければ nil。**
    #
    # 🔴 **スキームの無い照合も走査は進める**（投稿先も同じ）— ⚠⚠ **`a.com.https://b.com` の
    # `a.com` を飲んだ後から次を探す**ので、**照合そのものは捨てずに位置だけ使う。**
    def self.url_span(matched)
      return nil unless matched[:protocol]
      start, finish = matched.offset(:url)
      if (tco = matched[:url].match(TCO_PATTERN))
        return nil if tco[1].length > MAX_TCO_SLUG_LENGTH
        finish = start + tco[0].length
      end
      return start, finish
    end

    # URL 1 本を数えた形。
    #
    # - ⚠ **長すぎる URL・長すぎるラベル**は投稿先が URL と認めない → 素の長さ
    # - 🔴 **非 ASCII のホストは長いほう**（23 字と素の長さ）— ⚠⚠ **投稿先は libidn の `toASCII`
    #   （IDNA2003）に通し、失敗すれば URL と認めない**（Unicode 3.2 に無い文字・禁止文字）。
    #   **こちらで同じ判定を再現できない**ので、**どちらに転んでも短く数えない形を取る**
    # - それ以外は 23 字
    def self.url_length(url, domain)
      return url if url.length > MAX_URL_LENGTH
      return url if domain.split('.').any? {|label| label.length > MAX_LABEL_LENGTH}
      return [FOLDED, url].max_by {|value| value.grapheme_clusters.size} unless domain.ascii_only?
      return FOLDED
    end

    # ⚠ **twitter-text の文字の表**（`Twitter::TwitterText::Regex`）。
    UNICODE_SPACES = [
      '\u0009-\u000D\u0020\u0085\u00A0\u1680\u180E',
      '\u2000-\u200A\u2028\u2029\u202F\u205F\u3000',
    ].join.freeze
    DIRECTIONAL_CHARS = '\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069'.freeze
    INVALID_CHARS = '\uFFFE\uFEFF\uFFFF'.freeze

    # ⚠ **URL の直前に来てよい文字**（`valid_url_preceding_chars`）。🔴 **1 字を消費する**（後読みではない）。
    PRECEDING = "(?:[^A-Z0-9@＠$#＃#{INVALID_CHARS}]|[#{DIRECTIONAL_CHARS}]|^)".freeze

    # ⚠ **ホストに来てよい文字**（`DOMAIN_VALID_CHARS`）— ⚠⚠ **ASCII の記号・空白・制御文字以外は全部**
    # （🔴 **かなも漢字も入る**）。⚠ **`\` だけは記号の表から漏れていて、ホストに入る**（写し）。
    DOMAIN_CHAR = [
      '[^\\x00-\\x2F\\x3A-\\x40\\x5B\\x5D-\\x60\\x7B-\\x7F',
      "#{UNICODE_SPACES}#{DIRECTIONAL_CHARS}#{INVALID_CHARS}]",
    ].join.freeze

    # ⚠ **TLD の表は twitter-text 3.1.0 のもの**（`config/twitter-text/tld_lib.yml`）。🔴 **Public Suffix
    # List とは両方向にずれる**（PSL だけ: `.music` など・twitter-text だけ: `.za` など。2026-09-28 の実測で 18 / 144）ので、
    # **PSL から引くと、PSL が育つたびに短く数える形が増える**（makoto2#443 の `UNKNOWN_TLDS` はその片側だけ）。
    # ⚠⚠ **並び順も写す**（正規表現の選択肢の順）。
    TLDS = YAML.load_file(File.join(Environment.dir, 'config/twitter-text/tld_lib.yml')).freeze

    def self.tld_pattern(tlds)
      return "(?:(?:#{tlds.map {|tld| Regexp.escape(tld)}.join('|')})(?=[^0-9a-z@+-]|$))"
    end

    DOMAIN = [
      "(?:(?:#{DOMAIN_CHAR}(?:[_-]|#{DOMAIN_CHAR})*)?#{DOMAIN_CHAR}\\.)*",
      "(?:(?:#{DOMAIN_CHAR}(?:-|#{DOMAIN_CHAR})*)?#{DOMAIN_CHAR}\\.)",
      "(?:#{tld_pattern(TLDS['generic'])}|#{tld_pattern(TLDS['country'])}|(?:xn--[0-9a-z]+))",
    ].join.freeze

    # ⚠ **path の括弧**（twitter-text 本来の `valid_url_balanced_parens`）。🔴 **Mastodon は末尾の文字の
    # 表だけ、上書きする前のこちらを参照している**（定義の順のため）ので、両方要る。
    TWITTER_PATH_CHAR = [
      "[a-z\\p{Cyrillic}0-9!*';:=+,.$/%#\\[\\]\\p{Pd}_~&|@",
      # ⚠ `LATIN_ACCENTS`
      '\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u0253\u0254\u0256\u0257\u0259\u025B\u0263',
      '\u0268\u026F\u0272\u0289\u028B\u02BB\u0300-\u036F\u1E00-\u1EFF]',
    ].join.freeze

    def self.parens_pattern(char)
      return "\\((?:#{char}+|(?:#{char}*\\(#{char}+\\)#{char}*))\\)"
    end

    # ⚠ **Mastodon の上書き**（path は空白・`<>()?` 以外なら何でもよい）。
    PATH_CHAR = '[^\p{White_Space}<>()?]'.freeze
    PATH_PARENS = parens_pattern(PATH_CHAR).freeze
    PATH_ENDING = [
      "(?:[^\\p{White_Space}()?!*\"'「」<>;:=,.$%\\[\\]~&|]",
      "|#{parens_pattern(TWITTER_PATH_CHAR)})",
    ].join.freeze
    PATH = [
      "(?:(?:#{PATH_CHAR}*(?:#{PATH_PARENS}#{PATH_CHAR}*)*#{PATH_ENDING})",
      "|(?:#{PATH_CHAR}+/))",
    ].join.freeze

    # ⚠ **クエリに来てよい文字**（Mastodon の上書き・RFC 3987 の `ucschar` と私用領域を足した）。
    UCHARS = [
      '\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF\u{10000}-\u{1FFFD}\u{20000}-\u{2FFFD}',
      '\u{30000}-\u{3FFFD}\u{40000}-\u{4FFFD}\u{50000}-\u{5FFFD}\u{60000}-\u{6FFFD}',
      '\u{70000}-\u{7FFFD}\u{80000}-\u{8FFFD}\u{90000}-\u{9FFFD}\u{A0000}-\u{AFFFD}',
      '\u{B0000}-\u{BFFFD}\u{C0000}-\u{CFFFD}\u{D0000}-\u{DFFFD}\u{E1000}-\u{EFFFD}',
      '\uE000-\uF8FF\u{F0000}-\u{FFFFD}\u{100000}-\u{10FFFD}',
    ].join.freeze
    QUERY_CHAR = "[a-z0-9!?*'();:&=+$/%#\\[\\]\\-_.,~|@\\^#{UCHARS}]".freeze
    QUERY_ENDING = "[a-z0-9_&=#/\\-#{UCHARS}]".freeze

    # ⚠ **投稿先が URL と認めるスキーム**（Mastodon の上書き）。🔴 **スキームは無くても照合する**
    # （数えないが、走査は進む → `url_span`）。
    SCHEMES = ['https?', 'dat', 'dweb', 'ipfs', 'ipns', 'ssb', 'gopher', 'gemini'].freeze

    # ⚠ **スキームの付いた語の頭**（→ `unfolded_urls`）。
    SCHEME_START = %r{(?:#{SCHEMES.join('|')})://}i

    VALID_URL = Regexp.new(
      [
        "(?<before>#{PRECEDING})",
        '(?<url>',
        "(?<protocol>(?:#{SCHEMES.join('|')})://)?",
        "(?<domain>#{DOMAIN})",
        '(?::(?<port>[0-9]+))?',
        "(?<path>/#{PATH}*)?",
        "(?<query>\\?#{QUERY_CHAR}*#{QUERY_ENDING})?",
        ')',
      ].join,
      Regexp::IGNORECASE,
    )

    private_class_method :fold, :url_span, :url_length, :tld_pattern, :parens_pattern

    # 投稿先の申告と設定を突き合わせる（makoto2#351）。
    #
    # 🔴 **危ないのは申告のほうが短いときだけ**（取り込みは設定の上限で通すので、投稿の瞬間に
    # 422 ＝ 再送なしで枠が消える）。⚠ **長いぶんには弾きすぎるだけ。**⚠ **申告が無ければ判定しない。**
    #
    # @return [String, nil] ずれていれば、その説明
    def limit_mismatch(declared)
      return nil if declared.nil? || limit <= declared
      return "/mastodon/max_length は #{limit} 字だが、投稿先の申告は #{declared} 字"
    end

    def limit
      return config['/mastodon/max_length'].to_i
    end
  end
end
