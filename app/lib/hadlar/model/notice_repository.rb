module Hadlar
  # チャットボットの決まった文（→ `ChatGate::NOTICES` / `ChatOwnerNotice`）。
  #
  # ⚠ makoto2 では原稿の DB（`MessageRepository`・正本は private の makoto-scripts）から引いていた。
  # hadlar は原稿の DB を持たないので、YAML 1 枚（`/chat/notices/path`）から引く。
  # ⚠ 決まった文はボットのために書いた文で、原作の台詞ではない（原作の台詞はこのリポジトリに置かない）。
  #
  # 形は「type → 文の配列」。⚠ **無い・空・読めない type は空を返す**（→ 返す側が黙る）。
  class NoticeRepository
    include Package

    # @param path [String, nil] ⚠ テストが差し替える
    def initialize(path = nil)
      @path = path
    end

    # @return [Array<Hash>] `{body:}` の配列（`MessageRepository#by_type` と同じ形）
    def by_type(type)
      return Array(notices[type.to_s]).map(&:to_s).reject(&:empty?).map {|body| {body: body}}
    end

    def path
      @path ||= File.expand_path(config['/chat/notices/path'], Environment.dir)
      return @path
    end

    private

    def notices
      @notices ||= load
      return @notices
    end

    def load
      return {} unless File.file?(path)
      loaded = YAML.safe_load_file(path)
      return loaded.is_a?(Hash) ? loaded : {}
    rescue Psych::Exception => e
      logger.warn(chat: 'notice', message: 'unreadable notices', error_class: e.class.name)
      return {}
    end
  end
end
