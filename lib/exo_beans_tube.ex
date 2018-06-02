defmodule ExoBeans.Tube do
  @moduledoc ~S"""
   the logical "queue" for storing jobs. a tube responds to the incoming messages.

   a client can expect `info` replies from the dispatcher with spec `{:reply,{:tube, registered_tube_name :: atom()}, message :: binary()}`
  """
  alias ExoBeans.Server.Reply
  alias ExoBeans.Constants.ClientCommands
  alias :epqueue, as: Heap
  alias __MODULE__.Job.Reserved.Governer, as: ReservationManager
  alias __MODULE__.Job.Reserved.Registry, as: ProcessRegistry
  alias __MODULE__.Job.State

  use GenServer
  require Logger
  require ClientCommands

  @doc false
  def start_link(tube_name: name, data_table: table) do
    GenServer.start_link(__MODULE__, [name, table], name: name)
  end

  @doc false
  def init([tube_name, job_data_table]) do
    # the heap that stores the job meta
    # tell the queue that multiple process can access it.
    {:ok, ready_heap} = Heap.new(global_lock: true)

    # job_data, job_heap, tube_name, clients waiting for jobs
    {:ok, {job_data_table, ready_heap, tube_name, []}}
  end

  def handle_cast(
        {ClientCommands.job_save(), client_pid,
         {:job, job_id, job_priority, {job_id, job_ttr, job_state} = job_meta,
          job_data}},
        {job_data_table, ready_heap, tube, waiting_clients}
      ) do
    # send the response immediately
    Process.send(client_pid, ["INSERTED", job_id] |> build_client_response(), [
      :noconnect
    ])

    # regardless, put the job in the table
    :ets.insert(job_data_table, {job_id, job_data, nil})

    Logger.debug(fn ->
      "job_meta: #{inspect(job_meta)} job_delay: #{job_state.data.delay}"
    end)

    waiting_clients =
      if job_state.data.delay > 0 do
        Logger.debug(fn ->
          "#{job_id} is delayed by #{job_state.data.delay} secs"
        end)

        # queue the job after it has done the waiting
        Process.send_after(
          self(),
          {:heap_update, :insert,
           {{job_id, job_ttr, job_state |> State.wakeup()}, job_priority}},
          job_state.data.delay * 1000
        )

        waiting_clients
      else
        # insert the metadata into the ready heap
        {:ok, heap_job_ref} = ready_heap |> Heap.insert(job_meta, job_priority)
        # update the job_data_table with the heap ref
        update_heap_ref(job_data_table, job_id, heap_job_ref)

        # we just received a new job, see if there are any waiting clients
        case waiting_clients do
          # no waiting li
          [client | remaining] ->
            # inform client about the new job
            Process.send(client, tube |> job_available_notify(), [:noconnect])
            # send back the remaining
            remaining

          _ ->
            waiting_clients
        end
      end

    {:noreply, {job_data_table, ready_heap, tube, waiting_clients}}
  end

  def handle_cast(
        {ClientCommands.job_request(), client_pid, _},
        {job_data_table, ready_heap, tube, waiting_clients} = state
      ) do
    Logger.debug(fn ->
      "#{inspect(client_pid)} has requested for job #{inspect(tube)}"
    end)

    waiting_clients =
      case ready_heap |> Heap.pop() do
        {:ok, {job_id, job_ttr, job_state}, job_priority} ->
          [{_, {job_body_size, job_body}, _}] =
            :ets.lookup(job_data_table, job_id)

          Logger.debug(fn ->
            "#{inspect(client_pid)} has been granted #{job_id} ttr: #{job_ttr}"
          end)

          # send the response immediately that --
          # job has been reserved to the client
          Process.send(
            client_pid,
            build_client_response(
              ["RESERVED", job_id, job_body_size],
              job_body
            ),
            [:noconnect]
          )

          # attach a reservation process for the job
          reserved_metadata =
            {job_id, job_ttr, job_state |> State.reserve(client_pid)}

          {:ok, client_job_watcher} =
            attach_reservation_process([
              state,
              {reserved_metadata, job_priority}
            ])

          Logger.debug(fn ->
            "#{inspect(client_job_watcher)} is watching over the job #{job_id}"
          end)

          []

        {:error, reason} ->
          Logger.debug(fn ->
            "got error while retreiving root: #{reason}"
          end)

          []

        :undefined ->
          # no more jobs, put the client to waiting list for jobs
          [client_pid | waiting_clients]

        something_else ->
          Logger.debug(fn ->
            "no more jobs in #{inspect(tube)} for #{inspect(client_pid)} received: #{
              inspect(something_else)
            }"
          end)

          []
      end

    {:noreply, {job_data_table, ready_heap, tube, waiting_clients}}
  end

  def handle_cast(
        {ClientCommands.job_purge(), client_pid, job_id},
        {job_data_table, ready_heap, _, _} = state
      ) do
    Logger.debug(fn ->
      "got delete request from #{inspect(client_pid)}"
    end)

    # check if the job has been reserved by the client
    response =
      case Registry.lookup(ProcessRegistry, job_id) do
        # watcher already is alive
        # this means the ttr for the reservation has not expired
        [{reservation_watcher, :reservation_process}] ->
          # send the message to the watcher that  it's life is up!
          Process.send(
            reservation_watcher,
            {ClientCommands.job_purge(), client_pid},
            [:noconnect]
          )

          ["DELETED"] |> build_client_response

        # no reservation is yet.
        [] ->
          # check if the job exits
          # delete the data from the datatable
          case :ets.take(job_data_table, job_id) do
            [{_, _, job_heap_ref}] ->
              # remove it from the heap
              ready_heap |> Heap.remove(job_heap_ref)
              # get a response back
              ["DELETED"] |> build_client_response

            [] ->
              # may be the job doesn't exist?
              ["NOT_FOUND"] |> build_client_response
          end
      end

    Logger.debug(fn ->
      "purge of #{job_id} is finished"
    end)

    # send the response back
    Process.send(client_pid, response, [:noconnect])

    {:noreply, state}
  end

  def handle_info(
        {:heap_update, update, {{job_id, _, _} = job_metadata, job_priority}},
        {job_data_table, ready_heap, _, _} = state
      )
      when update == :insert do
    Logger.debug(fn ->
      ":heap_update with #{update} received for #{job_id}"
    end)

    {:ok, heap_job_ref} = ready_heap |> Heap.insert(job_metadata, job_priority)
    update_heap_ref(job_data_table, job_id, heap_job_ref)
    {:noreply, state}
  end

  def handle_call(
        :status,
        _from,
        {job_data_table, job_heap, _, waiting_clients} = state
      ) do
    data =
      case Heap.peek(job_heap) do
        {:ok, {job_id, job_ttr, _}, _} ->
          [id: job_id, max_ttr: job_ttr]

        _ ->
          nil
      end

    all_jobs = [
      waiting_clients: waiting_clients,
      next_available_job: data,
      reserved_jobs:
        ReservationManager
        |> Task.Supervisor.children()
        |> Enum.map(fn pid ->
          {pid, ProcessRegistry |> Registry.keys(pid) |> hd}
        end),
      job_data_table: :ets.tab2list(job_data_table)
    ]

    {:reply, all_jobs, state}
  end

  @doc false
  # the "logic" for watching for reserved jobs
  # this is run over a different process not the tube!
  def watch_reservation(
        {job_data_table, ready_heap, _, _} = arg1,
        {{job_id, job_ttr,
          %State{
            data: %{delay: _, r_pid: reserved_client},
            state: :reserved
          } = reserved_state}, job_priority}
      ) do
    # register itself to the proces registry with the job id
    Registry.register(ProcessRegistry, job_id, :reservation_process)

    Logger.debug(fn ->
      "watch_reservation: #{job_ttr}"
    end)

    # send the release_job after the timer has expired
    timer_ref = Process.send_after(self(), :release_job, job_ttr * 1000)

    if Process.get(:ttl) == nil do
      Process.put(:ttl, job_ttr)
      # send a deadline to client
      Process.send_after(self(), :send_client_deadline, (job_ttr - 1) * 1000)
    end

    receive do
      # client messages
      {ClientCommands.job_purge(), ^reserved_client} ->
        Logger.debug(fn ->
          "#{inspect(reserved_client)} has purged #{job_id}"
        end)

        # delete the data from the datatable
        :ets.delete(job_data_table, job_id)

      {ClientCommands.job_release(), ^reserved_client} ->
        Logger.debug(fn ->
          "#{inspect(reserved_client)} has released #{job_id}"
        end)

        send(self(), :release_job)

      # self messages
      {:ttl, client_pid} ->
        remain = Process.read_timer(timer_ref)

        Logger.debug(fn ->
          "#{inspect(self())} #{inspect(client_pid)} has requested ttl, ttl: #{
            remain
          }"
        end)

        send(client_pid, remain)
        # loop back, with remaining ttr
        # we loose some mills because of the rounding
        watch_reservation(
          arg1,
          {{job_id, Integer.floor_div(remain, 1000), reserved_state},
           job_priority}
        )

      :reset_ttl ->
        Logger.debug(fn ->
          "resetting ttr"
        end)

        # loop back & reset
        watch_reservation(
          arg1,
          {{job_id, Process.get(:ttl), reserved_state}, job_priority}
        )

      :send_client_deadline ->
        Process.send(
          reserved_client,
          ["DEADLINE_SOON"] |> build_client_response,
          [:noconnect]
        )

        # deadline is called exactly 1 sec before the end
        watch_reservation(
          arg1,
          {{job_id, 1, reserved_state}, job_priority}
        )

      :release_job ->
        Logger.debug(fn ->
          "got :release_job signal putting it back to heap"
        end)

        # put it back into the heap
        {:ok, heap_job_ref} =
          ready_heap
          |> Heap.insert(
            {job_id, Process.get(:ttl), reserved_state |> State.release()},
            job_priority
          )

        # update the table with the heap reference
        update_heap_ref(job_data_table, job_id, heap_job_ref)

        Logger.debug(fn ->
          "released #{job_id} "
        end)

      # other messages
      {:EXIT, from, reason} ->
        Logger.debug(fn ->
          "#{inspect(from)} has requested EXIT with reason #{inspect(reason)}"
        end)
    end
  end

  defp attach_reservation_process(args) when is_list(args) do
    Task.Supervisor.start_child(
      ReservationManager,
      __MODULE__,
      :watch_reservation,
      args
    )
  end

  defp update_heap_ref(job_table, job_id, new_ref) do
    :ets.update_element(job_table, job_id, {3, new_ref})
    # because :ets doesn't allow `update_element` for `duplicate_bag`
    # [{^job_id, job_data, _}] = :ets.lookup(job_table, job_id)
    # :ets.insert(job_table, {job_id, job_data, new_ref})
  end

  defp build_client_response(data) do
    {:reply, {:tube, self()}, Reply.serialize(data)}
  end

  defp build_client_response(data1, data2) do
    {:reply, {:tube, self()}, data1 |> Reply.serialize(data2)}
  end

  defp job_available_notify(tube) do
    {:reply, {:tube, tube}, :new_job}
  end
end
