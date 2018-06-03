defmodule ExoBeans.Test.BlackBox do
  use ExUnit.Case, async: true
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

    test "single delayed job :: put, reserve, delete" do
      {:ok, client} = :ebeanstalkd.connect([{:port, @server_port}])

      len = :rand.uniform(100)
      job_data = next_bytes(len)

      {:inserted, job_id} =
        client
        |> :ebeanstalkd.put(job_data, [{:pri, 0}, {:delay, 10}, {:ttr, 60}])

      {:reserved, ^job_id, ^job_data} = client |> :ebeanstalkd.reserve()

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
