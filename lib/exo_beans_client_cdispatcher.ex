defmodule ExoBeans.Client.Command.Dispatcher do
  @moduledoc """
  the dispatcher process responsible for parsing, processing & _forwarding_ commands to the respective tube process. the exact details on how it does lies opaue to the clients.

  a client can expect `info` replies from the dispatcher with spec `{:reply,:dispatcher, message :: binary()}`
  """
  alias ExoBeans.Tube.Registry, as: TubeRegistry
  alias ExoBeans.Server.Reply
  alias ExoBeans.Constants
  alias :poolboy, as: Pool
  alias ExoBeans.Constants.ClientCommands
  @timeout 60_000

  require Logger
  require Constants
  require ClientCommands
  use GenServer

  ### Client Apis

  @doc ~S"""
  to be called by the client process when it connects. this is neccessary as the dispatcher stores "certain" info about the client

  ## Examples

       iex>ExoBeans.Client.Command.Dispatcher.dispatch_command(:client_connect)
       :ok
  """
  def client_connected do
    dispatch_command(:client_connect)
  end

  @doc ~S"""
  to be called by the client process when it disconnects. useful for cleanups

  ## Examples

       iex>ExoBeans.Client.Command.Dispatcher.dispatch_command(:client_disconnect)
       :ok
  """
  def client_disconnect do
    dispatch_command(:client_disconnect)
  end

  @doc """
   to be called by the client process for "dispatching" the commands to the respective tube. See `ExoBeans.Constants.ClientCommands` for the commands that can be sent by client.

  ## Examples

       iex>ExoBeans.Client.Command.Dispatcher.dispatch_command(:client_connect)
       :ok
       iex>ExoBeans.Client.Command.Dispatcher.dispatch_command(:client_disconnect)
       :ok
  """
  @spec dispatch_command(
          dispatch_type :: atom(),
          arguments :: list(String.t()) | any()
        ) :: :ok
  def dispatch_command(dispatch_type, arguments \\ [])

  def dispatch_command(dispatch_type, arguments)
      when is_atom(dispatch_type) do
    client_pid = self()

    Pool.transaction(
      __MODULE__,
      fn pid ->
        GenServer.cast(pid, {dispatch_type, client_pid, arguments} |> msg())
      end,
      @timeout
    )

    :ok
  end

  @doc false
  # this is an explict notification from the tube of job availability,
  # send the request directly instead of asking for the dispatcher
  def dispatch_command(ClientCommands.job_request(), tube) do
    client_pid = self()
    GenServer.cast(tube, {ClientCommands.job_request(), client_pid, nil})
    :ok
  end

  ##### Internal methods
  @doc false
  def start_link([client_table]) do
    GenServer.start_link(__MODULE__, client_table, [])
  end

  @doc false
  def init(client_table) do
    {:ok, client_table}
  end

  def handle_cast({:dispatch, {:client_connect, client_pid, _}}, client_table) do
    :ets.insert(
      client_table,
      # clientpid -> current tube, watch tubes
      {client_pid, :default, MapSet.new() |> MapSet.put(:default)}
    )

    {:noreply, client_table}
  end

  def handle_cast(
        {:dispatch, {:client_disconnect, client_pid, _}},
        client_table
      ) do
    :ets.delete(client_table, client_pid)
    {:noreply, client_table}
  end

  #######

  def handle_cast(
        {:dispatch, {ClientCommands.tube_context(), client_pid, [tube_name]}},
        client_table
      ) do
    {:ok, {registered_tube, _}} = TubeRegistry.create_tube(tube_name)

    updated? =
      :ets.update_element(client_table, client_pid, {2, registered_tube})

    if updated? do
      Logger.debug(fn ->
        "tube changed: #{inspect(client_pid)} #{registered_tube}"
      end)

      :ok =
        Process.send(
          client_pid,
          ["USING", tube_name] |> build_client_response,
          [:noconnect]
        )
    else
      send_error(client_pid)
    end

    {:noreply, client_table}
  end

  def handle_cast(
        {:dispatch, {ClientCommands.job_request(), client_pid, _}},
        client_table
      ) do
    Logger.debug(fn -> "#{inspect(client_pid)}> requesting job" end)

    client_table
    |> :ets.lookup_element(client_pid, 3)
    |> MapSet.to_list()
    |> Enum.each(fn tube_pid ->
      tube_pid
      |> GenServer.cast({ClientCommands.job_request(), client_pid, nil})
    end)

    {:noreply, client_table}
  end

  def handle_cast(
        {:dispatch, {ClientCommands.tube_watch(), client_pid, [tube_name]}},
        client_table
      ) do
    {:ok, {registered_tube, _}} = TubeRegistry.create_tube(tube_name)

    Logger.debug(fn ->
      "#{inspect(client_pid)} watching #{registered_tube}"
    end)

    client_watch_list =
      client_table
      |> :ets.lookup_element(client_pid, 3)
      |> MapSet.put(registered_tube)

    updated? =
      :ets.update_element(client_table, client_pid, {3, client_watch_list})

    if updated? do
      Logger.debug(fn ->
        "watch list updated: #{inspect(client_pid)} #{
          inspect(client_watch_list)
        }"
      end)

      :ok =
        Process.send(
          client_pid,
          ["WATCHING", client_watch_list |> MapSet.size() |> to_string()]
          |> build_client_response,
          [:noconnect]
        )
    else
      send_error(client_pid)
    end

    {:noreply, client_table}
  end

  def handle_cast(
        {:dispatch, {_, client_pid, _} = dispatch_data},
        client_table
      ) do
    Logger.debug(fn ->
      "dispatching #{inspect(dispatch_data)} for #{inspect(client_pid)}"
    end)

    current_tube_of_client = :ets.lookup_element(client_table, client_pid, 2)
    GenServer.cast(current_tube_of_client, dispatch_data)
    {:noreply, client_table}
  end

  defp build_client_response(data) do
    {:reply, :dispatcher, Reply.serialize(data)}
  end

  defp msg(data) do
    {:dispatch, data}
  end

  defp send_error(client_pid) do
    Process.send(client_pid, ["INTERNAL_ERROR"] |> build_client_response, [
      :noconnect
    ])
  end
end
