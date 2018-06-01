defmodule ExoBeans.Governer do
  @moduledoc """
  the main supervisor governing all the other process in the application
  """
  use Supervisor
  @store_name Application.get_env(:exo_beans, :store_name)
  @client_metadata Application.get_env(:exo_beans, :client_metadata)
  @job_data_table Application.get_env(:exo_beans, :job_data_table)

  @doc false
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc false
  def init(_args) do
    init_application()

    children = [
      Supervisor.Spec.supervisor(
        ExoBeans.Tube.Registry,
        [],
        strategy: :one_for_all,
        restart: :permanent,
        name: TubeRegistry
      ),
      Supervisor.Spec.worker(
        ExoBeans.Server,
        [@store_name],
        strategy: :one_for_one,
        restart: :permanent,
        name: TcpServer
      ),
      :poolboy.child_spec(
        ExoBeans.Client.Command.Dispatcher,
        poolboy_config(),
        [@client_metadata]
      ),
      {
        Task.Supervisor,
        # Task supervisor for looking over reserved jobs
        strategy: :one_for_one,
        restart: :transient,
        name: ExoBeans.Tube.Job.Reserved.Governer
      },
      # start a registry to store the reservations
      {Registry, keys: :unique, name: ExoBeans.Tube.Job.Reserved.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp poolboy_config do
    [
      {:name, {:local, ExoBeans.Client.Command.Dispatcher}},
      {:worker_module, ExoBeans.Client.Command.Dispatcher},
      {:size, 3},
      {:max_overflow, 2}
    ]
  end

  defp init_application do
    # the metadata to be used by the dispatcher for storing client info
    :ets.new(@client_metadata, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # the place where the actual data resides
    :ets.new(@job_data_table, [
      :duplicate_bag,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  end
end
