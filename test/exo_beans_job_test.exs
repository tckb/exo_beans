defmodule ExoBeans.Test.Client do
  use ExUnit.Case, async: true
  alias ExoBeans.Tube.Registry
  alias ExoBeans.Constants, as: Constant
  alias Constant.Commands.Producer
  alias Constant.Commands.Worker
  alias Constant.Commands
  alias ExoBeans.Client.Command.Dispatcher
  alias ExoBeans.Constants.ClientCommands
  alias ExoBeans.Tube.Job
  alias ExoBeans.Server.Reply

  require Constant
  require Commands
  require Producer
  require Worker
  require ClientCommands

  doctest Dispatcher
  doctest Registry

  describe "[🧔 ⥂ 💻] " do
    test "connect & disconnect" do
      client_pid = new_client()
      send_ping(client_pid)

      # inform dispatcher that client is connected
      send(client_pid, {:client_command, :connected})

      # expect some metadata about the client to be stored
      [{^client_pid, default_tube, default_watch_list}] =
        get_client_meta(client_pid)

      {^default_tube, default_tube_pid} = Registry.find_tube(default_tube)
      # check if default tube is alive
      assert Process.alive?(default_tube_pid) == true

      # check if all the tubes in the watch list are actually alive
      default_watch_list
      |> MapSet.to_list()
      |> Enum.each(fn watch_tube ->
        {^watch_tube, watch_tube_pid} = Registry.find_tube(watch_tube)
        assert Process.alive?(watch_tube_pid) == true
      end)

      # inform dispatcher that client is connected
      send(client_pid, {:client_command, :disconnected})

      assert get_client_meta(client_pid) == []
    end

    test "put & reserve" do
      {:ok, {_, tube_pid}} = Registry.default_tube()

      client_pid = new_client()
      send_ping(client_pid)

      # create a job
      length = 1000
      some_data = next_bytes(length)
      delay = 0
      job = Job.new({length, some_data}, job_opts(delay, 1, 10))

      # inform dispatcher that client is connected
      send(client_pid, {:client_command, :connected})
      # client job save
      send(client_pid, {:client_command, {ClientCommands.job_save(), job}})

      # see if the job has been inserted
      assert_receive {{:tube, ^tube_pid}, data}, 1_000
      job_id = validate_replies(ClientCommands.job_save(), data)
      #
      # # job id is always a positive integer
      assert String.to_integer(job_id) > 0

      # now ask for reservation
      command = ClientCommands.job_request()
      send(client_pid, {:client_command, {command, []}})
      assert_receive {{:tube, ^tube_pid}, raw_job_data}, 1_000
      {^job_id, ^length, ^some_data} = validate_replies(command, raw_job_data)

      # inform dispatcher that client is connected
      send(client_pid, {:client_command, :disconnected})
    end
  end

  # describe "[🧔🧔🧔 ⥃ 💻] " do
  #   test "multiple tubes, put & reserve" do
  #     tube_context = "topic: #{:rand.uniform(1000)}"
  #
  #     client1 = new_client()
  #     send(client1, {:client_command, :connected})
  #
  #     send(
  #       client1,
  #       {:client_command, {ClientCommands.tube_context(), tube_context}}
  #     )
  #
  #     assert_receive {:dispatcher, data}, 1_000
  #     ^tube_context = validate_replies(ClientCommands.tube_context(), data)
  #
  #     # job insert
  #     j1 = new_job(100, init_delay: 0, priority: 0)
  #     send(client1, {:client_command, {ClientCommands.job_save(), j1}})
  #
  #     assert_receive {{:tube, _}, data}, 1_000
  #     j1_id = validate_replies(ClientCommands.job_save(), data)
  #
  #     assert j1_id > 0
  #     # job insert
  #     j2 = new_job(100, init_delay: 10, priority: 10)
  #     send(client1, {:client_command, {ClientCommands.job_save(), j2}})
  #     assert_receive {{:tube, _}, response}, 1_000
  #     j2_id = validate_replies(ClientCommands.job_save(), response)
  #
  #     assert j2_id > 0
  #     assert j1_id != j2_id
  #
  #     # new client
  #     client2 = new_client()
  #     send(client2, {:client_command, :connected})
  #
  #     # job request
  #     command = ClientCommands.job_request()
  #     send(client2, {:client_command, {command, []}})
  #     assert_receive {{:tube, _}, raw_job_data}, 1_000
  #     # j1 has the first priority
  #     {^j1_id, job_size, job_data} = validate_replies(command, raw_job_data)
  #     {:job, job_id, _, _, {job_body_size, job_body}} = j1
  #
  #     assert j1_id == job_id
  #     assert job_size == job_body_size
  #     assert job_body == job_data
  #
  #     # new job request
  #     command = ClientCommands.job_request()
  #     send(client2, {:client_command, {command, []}})
  #     assert_receive {{:tube, _}, raw_job_data}, 1_000
  #     # j1 has the first priority
  #     {^j2_id, job_size, job_data} = validate_replies(command, raw_job_data)
  #     {:job, job_id, _, _, {job_body_size, job_body}} = j2
  #
  #     assert j2_id == job_id
  #     assert job_size == job_body_size
  #     assert job_body == job_data
  #   end
  # end

  defp job_opts(job_delay, job_priority, job_ttr) do
    [priority: job_priority, time_to_run: job_ttr, init_delay: job_delay]
  end

  defp new_job(length, opts) do
    some_data = next_bytes(length)

    Job.new(
      {length, some_data},
      priority: Keyword.get(opts, :priority, 10),
      time_to_run: Keyword.get(opts, :time_to_run, 60),
      init_delay: Keyword.get(opts, :delay, 0)
    )
  end

  defp next_bytes(size) do
    0..size
    |> Enum.reduce("", fn _, acc ->
      acc <> (0..255 |> Enum.random() |> <<>>)
    end)
  end

  defp next_string(size) do
    0..size
    |> Enum.reduce("", fn _, acc ->
      acc <> (?a..?z |> Enum.random() |> <<>>)
    end)
  end

  defp get_client_meta(client_pid) do
    send(client_pid, {:admin_command, :dispatcher_status})
    assert_receive client_metadata, 1_000

    client_metadata
    |> Enum.filter(fn {pid, _, _} -> pid == client_pid end)
  end

  defp send_ping(pid) do
    # validate if the client is actually working
    send(pid, {:ping, self()})
    assert_receive :pong, 1_000
  end

  defp validate_replies(command, reply) do
    server_reply = Reply.deserialize(reply)

    case command do
      ClientCommands.job_save() ->
        assert ["INSERTED", job_id] = server_reply
        job_id

      ClientCommands.job_request() ->
        assert ["RESERVED", job_id, job_body_size, job_body] = server_reply
        {job_id, job_body_size, job_body}

      ClientCommands.tube_context() ->
        assert ["USING", some_tube] = server_reply
        some_tube
    end
  end

  defp new_client do
    spawn(__MODULE__, :client_loop, [self()])
  end

  def client_loop(calling_pid) do
    receive do
      {:ping, someone} ->
        send(someone, :pong)

      {:reply, from, data} ->
        send(calling_pid, {from, data})

      {:client_command, :connected} ->
        Dispatcher.client_connected()

      {:client_command, :disconnected} ->
        Dispatcher.client_disconnected()

      {:client_command, message} ->
        Dispatcher.dispatch_command(:client, message)

      {:admin_command, :dispatcher_status} ->
        Dispatcher.dispatch_command(:admin, {:status, []})

      data ->
        send(calling_pid, data)
    end

    client_loop(calling_pid)
  end
end
