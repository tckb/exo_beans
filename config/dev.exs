use Mix.Config

config :logger,
  level: :debug,
  backends: [:console],
  compile_time_purge_level: :debug

config :exo_beans, :stacktrace_depth, 20
