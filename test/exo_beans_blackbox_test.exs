defmodule ExoBeans.Test.BlackBox do
  use ExUnit.Case, async: false
  @server_port Application.get_env(:exo_beans, :port)
  alias ExoBeans.Constants.ClientCommands
  require ClientCommands

  describe "[🧔 ⥃ 💻] " do
    test "single job :: put, reserve, delete " do
      {:ok, client} = :ebeanstalkd.connect([{:port, @server_port}])

      tube = "tube:: #{:rand.uniform(1000)}"
      {:using, ^tube} = client |> :ebeanstalkd.use(tube)
      # 2 tubes, default + above tube
      {:watching, 2} = client |> :ebeanstalkd.watch(tube)

      len = :rand.uniform(100)
      job_data = next_bytes(len)

      {:inserted, job_id} = client |> :ebeanstalkd.put(job_data)

      {:reserved, ^job_id, ^job_data} = client |> :ebeanstalkd.reserve()

      {:deleted} = client |> :ebeanstalkd.delete(job_id)

      :ok = client |> :ebeanstalkd.close()
    end

    test "single delayed job :: put" do
      {:ok, client} = :ebeanstalkd.connect([{:port, @server_port}])

      len = :rand.uniform(100)
      job_data = next_bytes(len)
      job_delay_secs = 3

      {:inserted, job_id} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 0},
          {:delay, job_delay_secs},
          {:ttr, 100}
        ])

      :timer.sleep(job_delay_secs * 1000)
      {:reserved, ^job_id, ^job_data} = client |> :ebeanstalkd.reserve()

      :ok = client |> :ebeanstalkd.close()
    end

    test "multiple jobs :: put with priority" do
      {:ok, client} = :ebeanstalkd.connect([{:port, @server_port}])

      len = :rand.uniform(100)
      job_data = next_bytes(len)

      {:inserted, first_pri_job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 0},
          {:delay, 0},
          {:ttr, 100}
        ])

      {:inserted, third_pri_job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 10},
          {:delay, 0},
          {:ttr, 100}
        ])

      {:inserted, second_pri_job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 5},
          {:delay, 0},
          {:ttr, 100}
        ])

      {:reserved, ^first_pri_job, ^job_data} = client |> :ebeanstalkd.reserve()
      {:deleted} = client |> :ebeanstalkd.delete(first_pri_job)

      {:reserved, ^second_pri_job, ^job_data} = client |> :ebeanstalkd.reserve()
      {:deleted} = client |> :ebeanstalkd.delete(second_pri_job)

      {:reserved, ^third_pri_job, ^job_data} = client |> :ebeanstalkd.reserve()
      {:deleted} = client |> :ebeanstalkd.delete(third_pri_job)

      :ok = client |> :ebeanstalkd.close()
    end

    test "multiple job ::  put, delete & reserve" do
      {:ok, client} = :ebeanstalkd.connect([{:port, @server_port}])

      len = :rand.uniform(100)
      job_data = next_bytes(len)

      {:inserted, first_pri_job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 0},
          {:delay, 0},
          {:ttr, 100}
        ])

      {:inserted, third_pri_job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 10},
          {:delay, 0},
          {:ttr, 100}
        ])

      {:inserted, second_pri_job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 5},
          {:delay, 0},
          {:ttr, 100}
        ])

      {:reserved, ^first_pri_job, ^job_data} = client |> :ebeanstalkd.reserve()

      # now, delete the other jobs
      {:deleted} = client |> :ebeanstalkd.delete(second_pri_job)
      {:deleted} = client |> :ebeanstalkd.delete(third_pri_job)
      {:deleted} = client |> :ebeanstalkd.delete(first_pri_job)

      :ok = client |> :ebeanstalkd.close()
    end

    test "single job :: put, reserve with ttr expiry" do
      {:ok, client} = :ebeanstalkd.connect([{:port, @server_port}])

      len = :rand.uniform(100)
      job_data = next_bytes(len)
      job_time_to_run = 5

      {:inserted, job} =
        client
        |> :ebeanstalkd.put(job_data, [
          {:pri, 0},
          {:delay, 0},
          {:ttr, job_time_to_run}
        ])

      {:reserved, ^job, ^job_data} = client |> :ebeanstalkd.reserve()

      # block for more jobs, after `job_time_to_run-1` server will inform
      # that deadline for previous job is soon approching!
      {:deadline_soon} = client |> :ebeanstalkd.reserve()

      # do nothing! do not release the job, server will automatically release is
      # sleep, have a coffee or whatever
      :timer.sleep(2_000)

      # ask for reservation again, it will give the same job
      {:reserved, ^job, ^job_data} = client |> :ebeanstalkd.reserve()
      {:deleted} = client |> :ebeanstalkd.delete(job)

      :ok = client |> :ebeanstalkd.close()
    end
  end

  defp next_bytes(size) do
    0..size
    |> Enum.reduce("", fn _, acc ->
      acc <> (0..255 |> Enum.random() |> <<>>)
    end)
  end
end
