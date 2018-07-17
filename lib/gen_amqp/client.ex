defmodule GenAMQP.Client do
  @moduledoc """
  Client for consuming AMQP services
  """

  alias GenAMQP.Conn

  @spec call(GenServer.name(), String.t(), String.t(), Keyword.t()) :: any
  def call(sup_name, exchange, payload, opts \\ []) when is_binary(payload) do
    max_time = Keyword.get(opts, :max_time, 5_000)
    spec = {GenAMQP.Conn, nil}

    case DynamicSupervisor.start_child(sup_name, spec) do
      {:ok, pid} ->
        {:ok, correlation_id} = Conn.request(pid, exchange, payload, :default, opts)
        resp = wait_response(correlation_id, max_time)
        :ok = DynamicSupervisor.terminate_child(sup_name, pid)
        resp

      _ ->
        {:error, :amqp_conn}
    end
  end

  @spec call_with_conn(GenServer.name(), String.t(), String.t(), Keyword.t()) :: any
  def call_with_conn(conn_name, exchange, payload, opts \\ []) when is_binary(payload) do
    max_time = Keyword.get(opts, :max_time, 5_000)

    around_chan(conn_name, fn chan_name ->
      {:ok, correlation_id} = Conn.request(conn_name, exchange, payload, chan_name)
      wait_response(correlation_id, max_time)
    end)
  end

  @spec publish(GenServer.name(), String.t(), String.t(), Keyword.t()) :: any
  def publish(sup_name, exchange, payload, opts \\ []) when is_binary(payload) do
    spec = {GenAMQP.Conn, nil}

    case DynamicSupervisor.start_child(sup_name, spec) do
      {:ok, pid} ->
        Conn.publish(pid, exchange, payload, :default, opts)
        :ok = DynamicSupervisor.terminate_child(sup_name, pid)

      _ ->
        {:error, :amqp_conn}
    end
  end

  @spec publish_with_conn(GenServer.name(), String.t(), String.t(), Keyword.t()) :: any
  def publish_with_conn(conn_name, exchange, payload, _opts \\ []) when is_binary(payload) do
    around_chan(conn_name, fn chan_name ->
      Conn.publish(conn_name, exchange, payload, chan_name)
    end)
  end

  defp around_chan(conn_name, execute) do
    chan_name = UUID.uuid4()
    :ok = Conn.create_chan(conn_name, chan_name)
    resp = execute.(chan_name)
    :ok = Conn.close_chan(conn_name, chan_name)
    resp
  end

  defp wait_response(correlation_id, max_time) do
    receive do
      {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
        payload

      _ ->
        wait_response(correlation_id, max_time)
    after
      max_time ->
        {:error, :timeout}
    end
  end
end
