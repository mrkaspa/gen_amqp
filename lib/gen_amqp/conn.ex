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
  # @spec start_link(binary(), GenServer.name()) :: GenServer.on_start()
  def start_link(conn_url, name) do
    Logger.info("Crearing conn with name: #{name} and url #{conn_url}")
    GenServer.start_link(__MODULE__, [name, conn_url], name: name)
  end

  @doc """
  Creates a new channel
  """
  @spec create_chan(GenServer.name(), atom) :: any
  def create_chan(name, chan_name) do
    GenServer.call(name, {:create_chan, chan_name})
  end

  @doc """
  Closes a channel
  """
  @spec close_chan(GenServer.name(), atom) :: any
  def close_chan(name, chan_name) do
    GenServer.call(name, {:close_chan, chan_name})
  end

  @doc """
  Publish a message in an asynchronous way
  """
  @spec publish(GenServer.name(), String.t(), String.t(), atom) :: any
  def publish(name, exchange, payload, chan_name, opts \\ []) do
    GenServer.call(name, {:publish, exchange, payload, chan_name, opts})
  end

  @doc """
  Works like a request respone
  """
  @spec request(GenServer.name(), String.t(), String.t(), atom) :: any
  def request(name, exchange, payload, chan_name, opts \\ []) do
    GenServer.call(name, {:request, exchange, payload, chan_name, opts})
  end

  @doc """
  Response a given request
  """
  @spec response(GenServer.name(), map, String.t(), atom) :: any
  def response(name, meta, payload, chan_name) do
    GenServer.call(name, {:response, meta, payload, chan_name})
  end

  @doc """
  Subscribes to an specific queue
  """
  @spec subscribe(GenServer.name(), String.t(), atom) :: :ok
  def subscribe(name, exchange, chan_name) do
    GenServer.call(name, {:subscribe, exchange, chan_name})
  end

  @spec unsubscribe(GenServer.name(), String.t(), atom) :: any
  def unsubscribe(name, exchange, chan_name) do
    GenServer.call(name, {:unsubscribe, exchange, chan_name})
  end

  @spec ack(GenServer.name(), String.t(), map) :: any
  def ack(conn_name, chan_name, meta) do
    GenServer.call(conn_name, {:nack, chan_name, meta})
  end

  @spec nack(GenServer.name(), String.t(), map) :: any
  def nack(conn_name, chan_name, meta) do
    GenServer.call(conn_name, {:nack, chan_name, meta})
  end

  # Private API

  def init([name, amqp_url]) do
    Logger.info("Starting connection")
    Process.flag(:trap_exit, true)
    {:ok, conn} = AMQP.Connection.open(amqp_url)
    {:ok, chan} = AMQP.Channel.open(conn)

    if name != nil do
      case :ets.lookup(:conns, name) do
        [{_, connected}] -> reconnect(connected)
        _ -> :ok
      end
    end

    {:ok,
     %{conn: conn, conn_name: name, chans: %{default: chan}, subscriptions: %{}, queues: %{}}}
  end

  defp reconnect(connected) do
    Logger.info("restarting #{inspect(connected)}")

    for gen_name <- connected, gen_name != :default do
      GenServer.cast(gen_name, :reconnect)
    end
  end

  def handle_call({:create_chan, name}, _from, %{conn: conn} = state) do
    {:ok, chan} = AMQP.Channel.open(conn)
    new_state = update_in(state.chans, &Map.put(&1, name, chan))
    {:reply, :ok, new_state}
  end

  def handle_call({:close_chan, name}, _from, state) do
    :ok = AMQP.Channel.close(state.chans[name])
    new_state = update_in(state.chans, &Map.delete(&1, name))
    {:reply, :ok, new_state}
  end

  def handle_call({:publish, exchange, payload, chan_name, opts}, _from, %{chans: chans} = state) do
    chan = chans[chan_name]

    AMQP.Basic.publish(chan, "", exchange, payload, opts)
    {:reply, :ok, state}
  end

  def handle_call({:response, meta, payload, chan_name}, _from, %{chans: chans} = state) do
    chan = chans[chan_name]

    AMQP.Basic.publish(
      chan,
      "",
      meta.reply_to,
      payload,
      correlation_id: meta.correlation_id
    )

    {:reply, :ok, state}
  end

  def handle_call(
        {:request, exchange, payload, chan_name, opts},
        {pid_from, _},
        %{chans: chans} = state
      ) do
    chan = chans[chan_name]

    correlation_id =
      :erlang.unique_integer()
      |> :erlang.integer_to_binary()
      |> Base.encode64()

    {:ok, %{queue: queue_name}} =
      AMQP.Queue.declare(chan, "", exclusive: true, auto_delete: true, durable: false)

    AMQP.Basic.consume(chan, queue_name, pid_from, no_ack: true)

    AMQP.Basic.publish(
      chan,
      "",
      exchange,
      payload,
      Keyword.merge(
        [reply_to: queue_name, correlation_id: correlation_id],
        opts
      )
    )

    {:reply, {:ok, correlation_id}, state}
  end

  def handle_call(
        {:subscribe, exchange, chan_name},
        {pid_from, _},
        %{chans: chans, subscriptions: subscriptions, queues: queues} = state
      ) do
    chan = chans[chan_name]

    new_queues = Map.put_new(queues, pid_from, consume(pid_from, chan, exchange))

    new_subscriptions =
      subscriptions
      |> Map.put_new(exchange, [])
      |> Map.update!(exchange, fn subscribers ->
        case Enum.find_value(subscribers, nil, &(&1 == pid_from)) do
          nil ->
            subscribers

          _ ->
            [pid_from | subscribers]
        end
      end)

    new_state = %{state | subscriptions: new_subscriptions, queues: new_queues}
    {:reply, :ok, new_state}
  end

  def handle_call(
        {:unsubscribe, exchange, chan_name},
        {pid_from, _},
        %{chans: chans, subscriptions: subscriptions, queues: queues} = state
      ) do
    chan = chans[chan_name]

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
      |> Map.update!(exchange, fn subscribers ->
        Enum.reject(subscribers, &(&1 == pid_from))
      end)

    new_state = %{state | subscriptions: new_subscriptions, queues: new_queues}

    {:reply, :ok, new_state}
  end

  def handle_call(
        {:ack, chan_name, %{delivery_tag: delivery_tag}},
        _from,
        %{chans: chans} = state
      ) do
    chan = chans[chan_name]
    resp = AMQP.Basic.ack(chan, delivery_tag)
    {:reply, resp, state}
  end

  def handle_call(
        {:nack, chan_name, %{delivery_tag: delivery_tag}},
        _from,
        %{chans: chans} = state
      ) do
    chan = chans[chan_name]
    resp = AMQP.Basic.reject(chan, delivery_tag)
    {:reply, resp, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  def terminate(reason, %{conn_name: conn_name, chans: chans} = state) do
    Logger.info("Closing AMQP Connection reason: #{inspect(reason)}")

    if conn_name != nil do
      if reason in [:normal, :shutdown] or match?({:shutdown, _}, reason) do
        :ets.delete(:conns, conn_name)
      else
        :ets.insert(:conns, {conn_name, Map.keys(chans)})
      end
    end

    AMQP.Connection.close(state.conn)
    :ok
  end

  @spec consume(pid, struct, String.t()) :: String.t()
  defp consume(pid, chan, exchange) do
    {:ok, %{queue: queue_name}} = AMQP.Queue.declare(chan, exchange, durable: false)
    {:ok, _} = AMQP.Basic.consume(chan, queue_name, pid)
    queue_name
  end
end
