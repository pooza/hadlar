source 'https://rubygems.org'
# 下限: 実機（bydo / rubicon）と CI の Ruby が 4.0 系（4.0.6・YJIT 有効）。
# ⚠ 上限: メジャーは非互換が入りうるので、実機に入っていない系列で走らせない。
#   ⚠⚠ 事故が理由の pin ではない。外すのは「実機と CI の Ruby を 5.x にし、
#   当日通しリハーサルを 5.x で通した」とき（→ docs/CLAUDE.md の当日通し）。
ruby '>= 4.0', '< 5.0'
gem 'ginseng-core', github: 'pooza/ginseng-core', tag: 'v7.0.0', require: 'ginseng'
gem 'ginseng-fediverse', github: 'pooza/ginseng-fediverse', tag: 'v8.0.0',
  require: 'ginseng/fediverse'
# チャットボットの応答（makoto2#18）。⚠ **公式の Ruby SDK**（Messages API・structured outputs）。
# ⚠ 2.x は API 版 `2026-10-21` に合わせた系列。⚠ 出たばかりの版を避けて 2.3（2026-10-23）から。
gem 'anthropic', '~> 2.3.0'
gem 'rufus-scheduler'
# 例外の集約（makoto2#28）。⚠ **DSN が無ければ初期化しない**（→ `Hadlar.setup_sentry`）。
gem 'sentry-ruby'
gem 'sequel'
# rufus-scheduler の依存として入るが、Timetable が直接使うので明示する。
gem 'sqlite3'
gem 'tzinfo'
# 監視の口（MonitorServer）を常駐の中で起こすためだけに使う（makoto2#84）。
# ⚠ WebUI ではない。⚠⚠ 管理コンソールは作らないという決定は変えていない。
gem 'puma'
gem 'thor'

group :development do
  # 依存の脆弱性スキャン（makoto2#104）。⚠ **外部の advisory DB を引く**ので、
  # ⚠⚠ **`test.yml` には載せない** — **コードを 1 行も触っていないのに、DB が
  # 更新された日に緑が赤へ変わる**（→ `.github/workflows/audit.yml`）。
  gem 'bundler-audit', require: false
  # ⚠⚠ タグではなく SHA で固定する（pooza/ginseng-style#75）。タグは付け替えられる。
  gem 'ginseng-style', github: 'pooza/ginseng-style',
    ref: '127c2854e76811eeec41e21c7bf262b4a527d2b7', require: false # v1.1.15
  gem 'rubocop-sequel'
  gem 'test-unit'
  # テストで時刻を止めるためだけに使う（makoto2 では日付を騙すリハーサルに本番でも使っていた・hadlar は持たない）。
  gem 'timecop'
  gem 'webmock'
end
