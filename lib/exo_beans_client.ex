defmodule ExoBeans.Client do
  @moduledoc """
  the connected client. the client may be a producer or a worker depending on the commands he sends
  """

  alias ExoBeans.Constants, as: Constant
  alias Constant.Commands.Producer
  alias Constant.Commands.Worker
  alias Constant.Commands
  alias ExoBeans.Client.Command.Dispatcher
  alias ExoBeans.Constants.ClientCommands
  alias ExoBeans.Tube.Job

  use GenServer
  require Logger
  require Constant
  require Commands
  require Producer
  require Worker
  require ClientCommands

  @behaviour :ranch_protocol
  # carriage return
  @crlf "\r\n"
  @lf "\n"
  # space character
  @spc " "

  @doc false
  def start_link(ref, socket, transport, []) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, socket, transport])
    {:ok, pid}
  end

  @doc false
  def init(ref, socket, transport) do
    :ok = :ranch.accept_ack(ref)

    :ok =
      transport.setopts(socket, [
        # we want to receieve the data as it comes, push, instead of pull
        {:active, true},
        # enable TCP_NO_DELAY
        {:nodelay, true},
        # enable SOCKET REUSEADDR
        {:reuseaddr, true}
      ])

    Logger.debug(fn ->
      "#{inspect(socket)}> Connected. pid = #{inspect(self())}"
    end)

    Dispatcher.client_connected()

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport
    })
  end

  @doc false
  def handle_info(msg, state)

  def handle_info({:tcp, _socket, line}, state)
      when line == @crlf or line == @lf do
    {:noreply, state}
  end

  # when the client disconnects
  def handle_info({:tcp_closed, _}, state), do: close_client(state)
  def handle_info({:tcp, _, Commands.quit()}, state), do: close_client(state)

  defp close_client(%{socket: socket, transport: transport} = state) do
    Dispatcher.client_disconnected()
    transport.close(socket)
    {:stop, :normal, state}
  end

  ##########
  ## producer commands
  ##########

  def handle_info(
        {:tcp, _, Producer.use_tube() <> <<raw_tube_name::binary>>},
        state
      ) do
    [tube_name | _rest] = raw_tube_name |> String.split(@crlf)

    Dispatcher.dispatch_command(
      :client,
      {ClientCommands.tube_context(), tube_name}
    )

    {:noreply, state}
  end

  def handle_info(
        {:tcp, _, Producer.put() <> <<put_command_data::binary>>},
        state
      ) do
    [put_flags, job_data, _rest] = put_command_data |> String.split(@crlf)

    [job_priority, job_delay, job_ttr, job_body_size] =
      put_flags |> String.split(@spc)

    job_delay =
      if job_delay <= 0 do
        1
      else
        job_delay
      end

    job_ttr =
      if job_ttr <= 0 do
        1
      else
        job_ttr
      end

    job =
      Job.new(
        {job_body_size, job_data},
        priority: String.to_integer(job_priority),
        time_to_run: String.to_integer(job_ttr),
        init_delay: String.to_integer(job_delay)
      )

    Dispatcher.dispatch_command(:client, {ClientCommands.job_save(), job})
    {:noreply, state}
  end

  ##########
  ## worker commands
  ##########

  def handle_info(
        {:tcp, _, Worker.watch() <> <<raw_tube_name::binary>>},
        state
      ) do
    [tube_name | _rest] = raw_tube_name |> String.split(@crlf)

    Dispatcher.dispatch_command(
      :client,
      {ClientCommands.tube_watch(), tube_name}
    )

    {:noreply, state}
  end

  def handle_info({:tcp, _, Worker.reserve()}, state) do
    Dispatcher.dispatch_command(
      :client,
      {ClientCommands.job_request(), []}
    )

    {:noreply, state}
  end

  def handle_info({:tcp, _, Worker.delete() <> <<raw_job_id::binary>>}, state) do
    [job_id | _rest] = raw_job_id |> String.split(@crlf)

    Dispatcher.dispatch_command(
      :client,
      {ClientCommands.job_purge(), job_id}
    )

    {:noreply, state}
  end

  # don't respond any other messages
  def handle_info({:tcp, socket, data}, state) do
    Logger.debug(fn -> "#{inspect(socket)}> #{inspect(data)}" end)
    {:noreply, state}
  end

  ##########
  ### replies that are sent to the client
  ##########

  def handle_info({:reply, {:tube, tube}, :new_job}, state) do
    Logger.debug(fn ->
      "#{inspect(tube)} has new jobs, sending request"
    end)

    Dispatcher.dispatch_command(:tube, {ClientCommands.job_request(), tube})
    {:noreply, state}
  end

  # the reservation of a job coming directly from tube
  def handle_info(
        {:reply, {:tube, tube}, response},
        %{socket: socket, transport: transport} = state
      ) do
    Logger.debug(fn ->
      "received data from #{inspect(tube)} - #{inspect(response)}"
    end)

    transport.send(socket, response)
    {:noreply, state}
  end

  def handle_info(
        {:reply, from, response},
        %{socket: socket, transport: transport} = state
      ) do
    Logger.debug(fn ->
      "got reply from: #{from} -> #{inspect(response)}"
    end)

    transport.send(socket, response)
    {:noreply, state}
  end
end
