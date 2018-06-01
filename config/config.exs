# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :exo_beans,
  # Server settings
  port: 9999,
  accept_pool: 2

import_config "#{Mix.env()}.exs"
