defmodule GenAMQP.Chan do
  alias GenAMQP.Conn

  def publish(chan, exchange, route, payload, opts \\ []) do
    AMQP.Basic.publish(chan, exchange, route, payload, opts)
  end

  def request(chan, exchange, route, payload, pid_from, opts \\ []) do
    correlation_id =
      :erlang.unique_integer()
      |> :erlang.integer_to_binary()
      |> Base.encode64()

    with {:ok, %{queue: queue_name}} <-
           AMQP.Queue.declare(chan, "", exclusive: true, auto_delete: true, durable: false),
         {:ok, _} <- AMQP.Basic.consume(chan, queue_name, pid_from, no_ack: true),
         :ok <-
           publish(
             chan,
             exchange,
             route,
             payload,
             Keyword.merge(
               [reply_to: queue_name, correlation_id: correlation_id],
               opts
             )
           ) do
      {:ok, correlation_id}
    end
  end

  def response(chan, meta, payload) do
    AMQP.Basic.publish(
      chan,
      "",
      meta.reply_to,
      payload,
      correlation_id: meta.correlation_id
    )
  end

  def subscribe(conn_name, chan, queue_name, pid) do
    with {:ok, _} <- AMQP.Queue.declare(chan, queue_name, durable: false),
         {:ok, _} = AMQP.Basic.consume(chan, queue_name, pid, no_ack: false) do
      Conn.add_subscription(conn_name, pid)
      :ok
    end
  end

  def unsubscribe(conn_name, chan, queue_name, pid) do
    case AMQP.Queue.delete(chan, queue_name) do
      {:ok, _} ->
        Conn.remove_subscription(conn_name, pid)
        :ok

      _ ->
        {:error, :err_deleting_queue}
    end
  end
end
