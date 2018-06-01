use Mix.Config

config :logger,
  level: :error,
  backends: [:console],
  compile_time_purge_level: :error
