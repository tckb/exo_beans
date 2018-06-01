defmodule ExoBeans.Server do
  @moduledoc """
  the process responsible for booting up tcp the server
  """
  @listen_port Application.get_env(:exo_beans, :port)
  @connection_acceptor_pool_size Application.get_env(:exo_beans, :accept_pool)

  use GenServer
  require Logger

  @doc false
  def start_link(state \\ []) do
    case :ranch.start_listener(
           # reference of the server
           :exo_beans_server,
           # acceptor pool
           @connection_acceptor_pool_size,
           # TCP protocol handler, default from 'ranch'
           :ranch_tcp,
           [
             {:port, @listen_port},
             {:max_connections, :infinity}
           ],
           ExoBeans.Client,
           []
         ) do
      {:ok, pid} ->
        Logger.info("Started listener @#{@listen_port} pid: #{inspect(pid)}")
        {:ok, pid}

      {:error, err_msg} ->
        {:stop, {:error, err_msg}, []}
    end

    GenServer.start_link(__MODULE__, state, name: TcpServer)
  end

  @doc false
  def init(state) do
    # when the server starts, start the 'default' tube
    ExoBeans.Tube.Registry.create_tube(:default)
    {:ok, state}
  end

  defmodule Reply do
    @moduledoc """
    the module responsible for building responses that are sent to the client
    """
    @crlf "\r\n"
    @spc " "

    @doc """
      serializes the `data` in the format documented in [beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.txt)
    """
    @spec serialize(binary() | list(binary())) :: iolist()
    def serialize(data)

    def serialize(response_data_list) when is_list(response_data_list) do
      [response_data_list |> Enum.intersperse(@spc) | @crlf]
    end

    def deserialize(serialized_data) when is_list(serialized_data) do
      [serialized_reply | @crlf] = serialized_data

      serialized_reply
      |> Enum.flat_map(&String.split(&1, @spc))
      |> Enum.filter(&(String.length(&1) > 0))
    end

    @doc """
      serializes the `data1` & `data2` togather in the format documented in [beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.txt)
    """
    def serialize(data1, data2) when is_list(data1) and is_list(data2) do
      [
        [data1 |> Enum.intersperse(@spc) | @crlf]
        | [data2 |> Enum.intersperse(@spc) | @crlf]
      ]
    end
  end
end
