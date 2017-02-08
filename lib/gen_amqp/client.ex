defmodule GenAMQP.Client do
  @moduledoc """
  Client for consuming AMQP services
  """

  alias GenAMQP.Conn

  @spec call(String.t, String.t) :: any
  def call(exchange, payload) when is_binary(payload) do
    case Supervisor.start_child(GenAMQP.ConnSupervisor, []) do
      {:ok, pid} ->
        {:ok, correlation_id} = Conn.request(pid, exchange, payload)
        wait_response(pid, correlation_id)
      _ ->
        {:error, :amqp_conn}
    end
  end

  @spec publish(String.t, String.t) :: any
  def publish(exchange, payload) when is_binary(payload) do
    case Supervisor.start_child(GenAMQP.ConnSupervisor, []) do
      {:ok, pid} ->
        Conn.publish(pid, exchange, payload)
        :ok = Supervisor.terminate_child(GenAMQP.ConnSupervisor, pid)
      _ ->
        {:error, :amqp_conn}
    end
  end

  def wait_response(pid, correlation_id) do
    receive do
      {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
        :ok = Supervisor.terminate_child(GenAMQP.ConnSupervisor, pid)
        payload
      _ ->
        wait_response(pid, correlation_id)
    after
      5_000 ->
        :ok = Supervisor.terminate_child(GenAMQP.ConnSupervisor, pid)
        {:error, :timeout}
    end
  end
end
