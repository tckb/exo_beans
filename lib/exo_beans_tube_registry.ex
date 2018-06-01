defmodule ExoBeans.Tube.Registry do
  @moduledoc """
  the supervisor responsible for supervising the created tubes
  """
  @default_tube :default
  use DynamicSupervisor
  alias ExoBeans.Tube
  require Logger

  @type tube_t :: {tube_name :: atom(), tube_pid :: pid()}

  @doc false
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: []
    )
  end

  @doc """
  returns the default tube for the clients
  """
  @spec default_tube :: {:ok, tube_t}
  def default_tube do
    create_tube(@default_tube)
  end

  @doc """
  creates or returns tube with specified `name`.
  """
  @spec create_tube(tube_name :: binary() | atom()) :: {:ok, tube_t}
  def create_tube(name)

  def create_tube(name) when is_binary(name) do
    create_tube(String.to_atom(name))
  end

  def create_tube(name) when is_atom(name) do
    table = :"#{name}_job_data"

    case DynamicSupervisor.start_child(
           __MODULE__,
           {Tube, tube_name: name, data_table: table}
         ) do
      {:error, {:already_started, tube_pid}} ->
        {:ok, {name, tube_pid}}

      {:ok, new_pid} ->
        Logger.debug(fn -> "Starting tube #{name}@ #{inspect(new_pid)} " end)

        # create table that actually stores the data
        :ets.new(table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

        {:ok, {name, new_pid}}
    end
  end

  @doc """
   deletes the  tube with `tube_name`  given as pid or registered name

   ## Examples

        iex>{:ok, {:random_tube,tube_pid}} = ExoBeans.Tube.Registry.create_tube(:random_tube)
        iex>ExoBeans.Tube.Registry.delete_tube(:random_tube)
        :ok
        iex>ExoBeans.Tube.Registry.delete_tube(:unknown_tube)
        {:error, :not_found}
  """
  @spec delete_tube(tube_name :: binary() | atom() | pid()) ::
          :ok | {:error, :not_found}
  def delete_tube(tube_name)

  def delete_tube(tube_name) when is_binary(tube_name) do
    delete_tube(String.to_atom(tube_name))
  end

  def delete_tube(tube_name) when is_atom(tube_name) do
    case find_tube(tube_name) do
      {_, pid} ->
        delete_tube(pid)

      nil ->
        {:error, :not_found}
    end
  end

  def delete_tube(tube_name) when is_pid(tube_name) do
    DynamicSupervisor.terminate_child(__MODULE__, tube_name)
  end

  @doc """
   finds the tube with the given tube `name`
  """
  @spec find_tube(tube_name :: binary() | atom()) :: tube_t | nil
  def find_tube(name) when is_binary(name) do
    find_tube(String.to_existing_atom(name))
  rescue
    ArgumentError -> nil
  end

  def find_tube(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> nil
      pid -> {name, pid}
    end
  end

  @doc """
   returns the list of registered tubes
  """
  @spec tubes :: list(tube_t)
  def tubes do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} ->
      {Process.info(pid)[:registered_name], pid}
    end)
  end

  @doc """
  returns the number of registered tubes
  """
  @spec count() :: integer()
  def count do
    DynamicSupervisor.count_children(__MODULE__).workers
  end
end
