# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :exo_beans,
  # Server settings
  port: 9999,
  accept_pool: 2,
  client_metadata: :client_metadata,
  job_data_table: :job_table

import_config "#{Mix.env()}.exs"
