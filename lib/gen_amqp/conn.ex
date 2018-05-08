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
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, [nil])
  end

  @spec start_link(GenServer.name()) :: GenServer.on_start()
  def start_link(name) do
    GenServer.start_link(__MODULE__, [name], name: name)
  end

  @doc """
  Creates a new channel
  """
  @spec create_chan(GenServer.name(), atom) :: any
  def create_chan(name, chan_name) when is_atom(chan_name) do
    GenServer.call(name, {:create_chan, chan_name})
  end

  @doc """
  Closes a channel
  """
  @spec close_chan(GenServer.name(), atom) :: any
  def close_chan(name, chan_name) when is_atom(chan_name) do
    GenServer.call(name, {:close_chan, chan_name})
  end

  @doc """
  Publish a message in an asynchronous way
  """
  @spec publish(GenServer.name(), String.t(), String.t(), atom) :: any
  def publish(name, exchange, payload, chan_name) do
    GenServer.call(name, {:publish, exchange, payload, chan_name})
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

  # Private API

  def init([name]) do
    Logger.info("Starting connection")
    Process.flag(:trap_exit, true)
    amqp_url = Application.get_env(:gen_amqp, :amqp_url)
    {:ok, conn} = AMQP.Connection.open(amqp_url)
    {:ok, chan} = AMQP.Channel.open(conn)

    case :ets.lookup(:conns, name) do
      [{_, connected}] -> reconnect(connected)
      _ -> :ok
    end

    {:ok,
     %{conn: conn, conn_name: name, chans: %{default: chan}, subscriptions: %{}, queues: %{}}}
  end

  defp reconnect(connected) do
    Logger.info("restarting #{inspect(connected)}")

    for gen_name <- connected, gen_name != :default do
      IO.puts("gen #{gen_name}")
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

  def handle_call({:publish, exchange, payload, chan_name}, _from, %{chans: chans} = state) do
    chan = chans[chan_name]
    AMQP.Basic.publish(chan, "", exchange, payload)
    {:reply, :ok, state}
  end

  def handle_call({:response, meta, payload, chan_name}, _from, %{chans: chans} = state) do
    chan = chans[chan_name]
    AMQP.Basic.publish(chan, "", meta.reply_to, payload, correlation_id: meta.correlation_id)
    {:reply, :ok, state}
  end

  def handle_call(
        {:request, exchange, payload, chan_name, opts},
        {pid_from, _},
        %{chans: chans} = state
      ) do
    chan = chans[chan_name]
    app_id = Keyword.get(opts, :app_id, "v1.0")

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
      reply_to: queue_name,
      correlation_id: correlation_id,
      app_id: app_id
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
    {:ok, _} = AMQP.Basic.consume(chan, queue_name, pid, no_ack: true)
    queue_name
  end
end
