defmodule GenAMQP.Client do
  @moduledoc """
  Client for consuming AMQP services
  """

  alias GenAMQP.Conn

  @spec call_with_conn(GenServer.name(), String.t(), String.t(), Keyword.t()) :: any
  def call_with_conn(conn_name, exchange, payload, opts \\ []) when is_binary(payload) do
    max_time = Keyword.get(opts, :max_time, 5_000)

    around_chan(conn_name, fn chan ->
      {:ok, correlation_id} = Conn.request(conn_name, exchange, payload, chan)
      wait_response(correlation_id, max_time)
    end)
  end

  @spec publish_with_conn(GenServer.name(), String.t(), String.t(), Keyword.t()) :: any
  def publish_with_conn(conn_name, exchange, payload, _opts \\ []) when is_binary(payload) do
    around_chan(conn_name, fn chan ->
      Conn.publish(conn_name, exchange, payload, chan)
    end)
  end

  defp around_chan(conn_name, execute) do
    chan_name = UUID.uuid4()
    {:ok, chan} = Conn.create_chan(conn_name, chan_name, store: false)

    try do
      execute.(chan)
    after
      :ok = Conn.close_chan(conn_name, chan)
    else
      resp -> resp
    end
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
