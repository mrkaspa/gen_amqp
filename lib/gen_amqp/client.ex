defmodule GenAMQP.Client do
  @moduledoc """
  Client for consuming AMQP services
  """

  alias GenAMQP.Conn

  @doc """
  Executes a synchronous call to amqp queue
  """
  @spec call(String.t, String.t) :: any
  def call(exchange, payload) do
    {:ok, pid} = GenAMQP.Conn.start_link()
    {:ok, correlation_id} = Conn.request(pid, exchange, payload)
    wait_response(pid, correlation_id)
  end

  @doc """
  Executes an asynchronous call to amqp queue
  """
  @spec publish(String.t, String.t) :: any
  def publish(exchange, payload) do
    {:ok, pid} = GenAMQP.Conn.start_link()
    Conn.publish(pid, exchange, payload)
    GenServer.cast(pid, :stop)
  end

  defp wait_response(pid, correlation_id) do
    receive do
      {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
        GenServer.cast(pid, :stop)
        payload
      _ -> wait_response(pid, correlation_id)
    end
  end
end
