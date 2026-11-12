require 'webmock'

module Hadlar
  class TestCase < Ginseng::TestCase
    include Package
    include WebMock::API

    # ⚠ テストから外部へ実際のリクエストを飛ばさない。hadlar は投稿するボットなので、
    # 取りこぼすと本物のサーバーに書き込む（実際に 10 通投げてしまった）。
    #
    # `require 'webmock'` だけでは HTTP アダプタは差し替わらない。**`WebMock.enable!` を
    # 呼ぶまで `disable_net_connect!` も stub_request も無言で素通りする。**
    #
    # ⚠ **`setup` メソッドではなくコールバックで登録する。**メソッドにすると、
    # サブクラスが `setup` を定義して `super` を忘れた瞬間に遮断が外れる。
    # 忘れても落ちないので、素通しになったことに気付けない。
    setup do
      WebMock.enable!
      WebMock.disable_net_connect!
      quiet_chat
    end

    teardown do
      WebMock.reset!
      WebMock.allow_net_connect!
      WebMock.disable!
      @empty_db&.disconnect
      config.reload
    end

    # 🔴 **チャットボットは切り、キーも空にしておく**（makoto2#18）。⚠⚠ **手元の `local.yaml` にはキーがあり、
    # CI の雛形には無い**ので、そろえないと `Health` の警告が機械ごとに変わる（PR makoto2#589 の CI で踏んだ）。
    # ⚠ チャットのテストは、要る設定を自分で入れる。⚠ **`config.reload` のあとは呼び直す**（上書きが消える）。
    def quiet_chat
      config['/chat/enabled'] = false
      config['/chat/follow/enabled'] = false
      config['/anthropic/api_key'] = ''
    end

    # スキーマだけ当てた空の DB。投入そのものを見るテストが使う。
    def empty_db
      @empty_db ||= Database.migrate(Database.connect('sqlite:/'))
      return @empty_db
    end
  end
end
