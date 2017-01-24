defmodule GenAMQP.Client do
  @moduledoc """
  Client for consuming AMQP services
  """

  alias GenAMQP.Conn

  @spec call(String.t, String.t) :: any
  def call(exchange, payload) do
    {:ok, pid} = Supervisor.start_child(GenAMQP.Supervisor, [])
    {:ok, correlation_id} = Conn.request(pid, exchange, payload)
    wait_response(pid, correlation_id)
  end

  @spec publish(String.t, String.t) :: any
  def publish(exchange, payload) do
    {:ok, pid} = Supervisor.start_child(GenAMQP.Supervisor, [])
    Conn.publish(pid, exchange, payload)
    :ok = Supervisor.terminate_child(GenAMQP.Supervisor, pid)
  end

  def wait_response(pid, correlation_id) do
    receive do
      {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
        :ok = Supervisor.terminate_child(GenAMQP.Supervisor, pid)
        payload
      _ ->
        wait_response(pid, correlation_id)
    after
      10_000 ->
        :ok = Supervisor.terminate_child(GenAMQP.Supervisor, pid)
        {:error, :timeout}
    end
  end
end
