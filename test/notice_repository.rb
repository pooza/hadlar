require 'tmpdir'

module Hadlar
  class NoticeRepositoryTest < TestCase
    def with_notices(text)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'notices.yaml')
        File.write(path, text)
        yield NoticeRepository.new(path)
      end
    end

    def test_by_type
      with_notices("chat_ask_follow:\n  - 一\n  - ''\n  - 二\n") do |notices|
        assert_equal([{body: '一'}, {body: '二'}], notices.by_type('chat_ask_follow'))
        assert_equal([{body: '一'}, {body: '二'}], notices.by_type(:chat_ask_follow))
        assert_empty(notices.by_type('chat_limit_notice'))
      end
    end

    # ⚠ 1 本だけなら配列でなくてもよい。
    def test_a_single_body
      with_notices("chat_ask_follow: 一\n") do |notices|
        assert_equal([{body: '一'}], notices.by_type('chat_ask_follow'))
      end
    end

    # 🔴 **無い・読めないファイルでは空**（返す側が黙る）。
    def test_missing_or_broken_files_are_empty
      assert_empty(NoticeRepository.new('/nonexistent/notices.yaml').by_type('chat_ask_follow'))
      with_notices("chat_ask_follow: [\n") do |notices|
        assert_empty(notices.by_type('chat_ask_follow'))
      end
      with_notices("- 一\n") do |notices|
        assert_empty(notices.by_type('chat_ask_follow'))
      end
    end

    # ⚠ リポジトリに置いた文には、門が返す 4 つとオーナーへの知らせが揃っている。
    def test_the_shipped_notices_cover_every_type
      notices = NoticeRepository.new

      (ChatGate::NOTICES.values + [ChatOwnerNotice::OWNER_NOTICE_TYPE]).each do |type|
        assert_not_empty(notices.by_type(type), type)
      end
    end
  end
end
