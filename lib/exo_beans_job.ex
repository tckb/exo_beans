defmodule ExoBeans.Tube.Job do
  @moduledoc """
  defines the actual job for processing within a tube
  """
  alias __MODULE__
  require Logger

  @typedoc """
  a unique identifier representing the job. this is integer represented in string
  """
  @type job_id_t :: String.t()

  @typedoc """
   the meteadata describing the  job
  """
  @type job_metadata_t ::
          {job_id :: job_id_t, job_max_time_to_run :: pos_integer(),
           job_state :: %__MODULE__.State{
             data: %{delay: pos_integer(), r_pid: pid()},
             state: :delayed | :ready | :reserved | :buried | :terminated
           }}

  @type job_opts_t :: [
          priority: pos_integer(),
          time_to_run: pos_integer(),
          init_delay: pos_integer()
        ]

  @typedoc """
    defines a job data
  """
  @type job_t ::
          {:job, job_id :: job_id_t, job_priority :: pos_integer(),
           job_meta :: job_metadata_t, job_data :: any()}

  @doc """
  creates a new job with `job_data` with the `list` of options
  """
  @spec new(job_data :: any(), job_opts_t) :: job_t
  def new(
        job_data,
        priority: job_priority,
        time_to_run: job_ttr,
        init_delay: job_delay
      ) do
    job_id = to_string(:os.system_time())
    job_meta = {job_id, job_ttr, job_delay |> get_state()}
    {:job, job_id, job_priority, job_meta, job_data}
  end

  defp get_state(delay) do
    if delay > 0 do
      Job.State.new()
      |> Job.State.delay(delay)
    else
      Job.State.new()
    end
  end

  defmodule State do
    @moduledoc false
    use Fsm,
      initial_state: :ready,
      # {delay_interval, reservation_pid}
      initial_data: %{delay: 0, r_pid: nil}

    defstate delayed do
      @doc """
      wakes up a delayed job
      """
      defevent wakeup do
        next_state(:ready, %{delay: 0, r_pid: nil})
      end
    end

    defstate ready do
      @doc """
      reserves the current job for the specified `client_pid`
      """
      defevent reserve(client_pid) do
        next_state(:reserved, %{delay: 0, r_pid: client_pid})
      end

      @doc """
      `delays` the current job `delay` seconds
      """
      defevent delay(delay) do
        next_state(:delayed, %{delay: delay, r_pid: nil})
      end
    end

    defstate reserved do
      @doc """
      releases an already reserved job
      """
      defevent release do
        next_state(:ready, %{delay: 0, r_pid: nil})
      end

      @doc """
      burries the current job
      """
      defevent bury do
        next_state(:buried)
      end

      @doc """
      marks the current job for deletion. the actual deletion will be taken cared by tube
      """
      defevent delete do
        next_state(:terminated)
      end
    end

    defstate buried do
      @doc """
      wakes up a `buried` job
      """
      defevent kick do
        next_state(:ready)
      end

      @doc """
      marks the current job for deletion. the actual deletion will be taken cared by tube
      """
      defevent delete do
        next_state(:terminated)
      end
    end

    defstate terminated do
      defevent(_, do: raise("Job terminated"))
    end
  end
end
