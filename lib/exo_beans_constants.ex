defmodule ExoBeans.Constants do
  @moduledoc """
  the constants that are shared across all the modules
  """
  use ExoBeans.Const

  @doc """
   the default tube that is to be picked if no tube is specified
  """
  constant(default_tube, "default")

  @doc """
  the tube context key
  """
  constant(context_key, :current_tube)

  @doc """
  the key to be used for storing the tube subscription of workers
  """
  constant(worker_sub_key, :worker_sub)

  defmodule Commands do
    @moduledoc """
    the commands that are common for both producer & workers
    """
    @crlf "\r\n"
    @doc """
    the command for calling it quits
    """
    constant(quit, "quit" <> @crlf)

    defmodule Producer do
      @moduledoc """
      the commands that are issued by Producer
      """
      @spc " "

      @doc """
      the command for selecting the context of the job
      """
      constant(use_tube, "use" <> @spc)

      @doc """
      the command for putting a job into the selected "tube", aka "context"
      """
      constant(put, "put" <> @spc)
    end

    defmodule Worker do
      @moduledoc """
      the commands that are issued by the worker
      """
      @spc " "
      @crlf "\r\n"

      @doc """
      the comand for asking the reservation onto the selected tube
      """
      constant(reserve, "reserve" <> @crlf)

      @doc """
      the command for watching a tube for jobs
      """
      constant(watch, "watch" <> @spc)

      @doc """
      the command for deleting a job specified by the id
      """
      constant(delete, "delete" <> @spc)
    end
  end

  defmodule ClientCommands do
    @moduledoc false

    constant(tube_context, :tube_context)
    constant(tube_watch, :tube_watch)
    constant(tube_unwatch, :tube_unwatch)
    constant(job_request, :job_request)
    constant(job_save, :job_save)
    constant(job_purge, :job_purge)
    constant(job_release, :job_release)
  end
end
