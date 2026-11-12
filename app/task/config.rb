module Hadlar
  extend Rake::DSL
  include Package

  namespace :config do
    desc 'lint local config'
    task :lint do
      puts "environment: #{Environment.type}"
      # 🔴 **`validation_errors` を見る**（makoto2#612・Codex の P2）。⚠⚠ **`errors` は schema だけ**で、
      # 期間の書き損じ（`Config#duration_errors`）を拾わない。⚠ 起動時の検査・`/healthz` と同じ口。
      found = config.validation_errors
      if found.present?
        puts 'config:'
        puts found.to_yaml
        exit 1
      else
        puts 'config: OK'
      end
    end
  end
end
