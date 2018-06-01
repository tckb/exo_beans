defmodule ExoBeans.Test.Basic do
  use ExUnit.Case, async: true
  alias ExoBeans.Tube
  alias ExoBeans.Tube.Job
  alias ExoBeans.Tube.Job.State, as: JobState
  alias ExoBeans.Tube.Registry, as: TubeRegistry
  require Record
  require Job

  doctest Job
  doctest Tube
  doctest JobState
  doctest TubeRegistry
  doctest ExoBeans.Client.Command.Dispatcher

  test "create a job" do
    # generate some binary data
    length = :rand.uniform(100)
    some_data = next_bytes(length)
    # create a job
    {:job, job_id, job_priority, job_meta, job_data} =
      Job.new({length, some_data}, job_opts(1, 10, 20))

    assert {^job_id, job_ttr, job_state} = job_meta

    # check the job metadata
    assert job_priority == 10
    assert job_ttr == 20
    assert job_state.data.delay == 1
    assert job_state.state == :delayed
    # check the job data
    assert job_data == {length, some_data}

    new_job_state = job_state |> JobState.wakeup()

    # check the job metadata
    assert new_job_state.data.delay == 0
    assert new_job_state.state == :ready
  end

  test "reserve a new job" do
    # generate some binary data
    length = :rand.uniform(100)
    some_data = next_bytes(length)

    {:job, _, _, {_, _, job_state}, _} =
      Job.new({length, some_data}, job_opts(0, 10, 20))

    # check the job metadata
    assert job_state.data.delay == 0
    assert job_state.state == :ready

    new_job_state = job_state |> JobState.reserve(self())

    assert new_job_state.state == :reserved
    assert new_job_state.data.r_pid == self()

    new_job_state = new_job_state |> JobState.release()

    assert new_job_state.state == :ready
    assert new_job_state.data.r_pid == nil
  end

  test "create a tube" do
    # try creating multiple tubes with the same name
    tube_name = next_string(8)
    tube_name_atom = String.to_atom(tube_name)

    {:ok, {^tube_name_atom, pid1}} = TubeRegistry.create_tube(tube_name)
    {:ok, {^tube_name_atom, ^pid1}} = TubeRegistry.create_tube(tube_name_atom)

    assert TubeRegistry.find_tube(tube_name_atom) == {tube_name_atom, pid1}
    assert Keyword.fetch!(TubeRegistry.tubes(), tube_name_atom) == pid1

    tube_name = next_string(8)
    tube_name_atom = String.to_atom(tube_name)

    {:ok, {tube_name_atom, pid3}} = TubeRegistry.create_tube(tube_name_atom)
    assert TubeRegistry.find_tube(tube_name_atom) == {tube_name_atom, pid3}
    assert TubeRegistry.delete_tube(tube_name_atom) == :ok
    assert TubeRegistry.delete_tube(tube_name_atom) == {:error, :not_found}
    assert TubeRegistry.find_tube(tube_name_atom) == nil
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

  defp job_opts(job_delay, job_priority, job_ttr) do
    [priority: job_priority, time_to_run: job_ttr, init_delay: job_delay]
  end
end
