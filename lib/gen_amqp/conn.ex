defmodule GenAMQP.Conn do
  @moduledoc """
  Handles the internals for AMQP connections
  """

  use GenServer
  require Logger

  # Public API

  @doc """
  Starts the connection
  """
  @spec start_link(GenServer.name) :: GenServer.on_start
  def start_link(name \\ nil) do
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @doc """
  Publish a message in an asynchronous way
  """
  @spec publish(GenServer.name, String.t, String.t) :: any
  def publish(name, exchange, payload) do
    GenServer.call(name, {:publish, exchange, payload})
  end

  @doc """
  Works like a request respone
  """
  @spec request(GenServer.name, String.t, String.t) :: any
  def request(name, exchange, payload) do
    GenServer.call(name, {:request, exchange, payload})
  end

  @doc """
  Response a given request
  """
  @spec response(GenServer.name, map, String.t) :: any
  def response(name, meta, payload) do
    GenServer.call(name, {:response, meta, payload})
  end

  @doc """
  Subscribes to an specific queue
  """
  @spec subscribe(GenServer.name, String.t) :: :ok
  def subscribe(name, exchange) do
    GenServer.call(name, {:subscribe, exchange})
  end

  @spec unsubscribe(GenServer.name, String.t) :: any
  def unsubscribe(name, exchange) do
    GenServer.call(name, {:unsubscribe, exchange})
  end

  # Private API

  def init(_) do
    Process.flag(:trap_exit, true)
    config = Application.get_env(:gen_amqp, __MODULE__)
    {:ok, conn} = AMQP.Connection.open(config[:amqp_url])
    {:ok, chan} = AMQP.Channel.open(conn)
    {:ok, %{conn: conn, chan: chan, subscriptions: %{}, queues: %{}}}
  end

  def handle_call({:publish, exchange, payload}, _from, %{chan: chan} = state) do
    AMQP.Basic.publish(chan, "", exchange, payload)
    {:reply, :ok, state}
  end

  def handle_call({:response, meta, payload}, _from, %{chan: chan} = state) do
    AMQP.Basic.publish(chan, "", meta.reply_to, payload, correlation_id: meta.correlation_id)
    {:reply, :ok, state}
  end

  def handle_call({:request, exchange, payload}, {pid_from, _}, %{chan: chan} = state) do
    correlation_id =
      :erlang.unique_integer
      |> :erlang.integer_to_binary
      |> Base.encode64

    {:ok, %{queue: queue_name}} = AMQP.Queue.declare(chan, "", exclusive: true)
    AMQP.Basic.consume(chan, queue_name, pid_from, no_ack: true)

    AMQP.Basic.publish(chan, "", exchange, payload,
                      reply_to: queue_name, correlation_id: correlation_id)

    {:reply, {:ok, correlation_id}, state}
  end


  def handle_call({:subscribe, exchange}, {pid_from, _},
    %{chan: chan, subscriptions: subscriptions, queues: queues} = state) do
    new_queues =
      Map.put_new_lazy(queues, pid_from, fn ->
        consume(pid_from, chan, exchange)
      end)

    new_subscriptions =
      subscriptions
      |> Map.put_new(exchange, [])
      |> Map.update!(exchange, fn(subscribers) ->
        case Enum.find_value(subscribers, nil, &(&1 == pid_from)) do
          nil ->
            subscribers
          _ ->
            [pid_from | subscribers]
        end
      end)

    new_state =
      %{state | subscriptions: new_subscriptions, queues: new_queues}

    {:reply, :ok, new_state}
  end

  def handle_call({:unsubscribe, exchange}, {pid_from, _},
    %{chan: chan, subscriptions: subscriptions, queues: queues} = state) do

    new_queues =
      case Map.fetch(queues, pid_from) do
        {:ok, queue_name} ->
          AMQP.Queue.delete(chan, queue_name)
          Map.delete(queues, pid_from)
        _ ->
        queues
      end


    new_subscriptions =
      subscriptions
      |> Map.put_new(exchange, [])
      |> Map.update!(exchange, fn(subscribers) ->
        Enum.reject(subscribers, &(&1 == pid_from))
      end)

    new_state =
      %{state | subscriptions: new_subscriptions, queues: new_queues}

    {:reply, :ok, new_state}
  end

  def terminate(_reason, state) do
    Logger.info("Closing AMQP Connection")
    AMQP.Connection.close(state.conn)
    :ok
  end

  @spec consume(pid, struct, String.t) :: {:ok, any}
  defp consume(pid, chan, exchange) do
    {:ok, %{queue: queue_name}} = AMQP.Queue.declare(chan, exchange)
    {:ok, _} = AMQP.Basic.consume(chan, queue_name, pid, no_ack: true)
    queue_name
  end
end
