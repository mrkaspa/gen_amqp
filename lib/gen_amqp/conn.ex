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
  @spec create_chan(GenServer.name(), atom(), KeyError.t()) :: {:ok, AMQP.Channel.t()}
  def create_chan(name, chan_name, opts \\ []) do
    GenServer.call(name, {:create_chan, chan_name, opts})
  end

  @doc """
  Closes a channel
  """
  @spec close_chan(GenServer.name(), String.t() | AMQP.Channel.t()) :: any()
  def close_chan(name, chan) do
    GenServer.call(name, {:close_chan, chan})
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

  # Private API

  def init([name, amqp_url]) do
    Logger.info("Starting connection")
    Process.flag(:trap_exit, true)
    {:ok, %AMQP.Connection{pid: pid} = conn} = AMQP.Connection.open(amqp_url)
    Process.link(pid)
    Logger.info("Connection linked #{inspect(pid)}")
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

    for gen_name <- connected do
      GenServer.cast(gen_name, :reconnect)
    end
  end

  def handle_call({:create_chan, name, opts}, _from, %{conn: conn} = state) do
    {:ok, chan} = resp = AMQP.Channel.open(conn)
    store = Keyword.get(opts, :store, true)

    if store do
      new_state = update_in(state.chans, &Map.put(&1, name, chan))
      {:reply, :ok, new_state}
    else
      {:reply, resp, state}
    end
  end

  def handle_call({:close_chan, name}, _from, state) when is_binary(name) or is_atom(name) do
    :ok = AMQP.Channel.close(state.chans[name])
    new_state = update_in(state.chans, &Map.delete(&1, name))
    {:reply, :ok, new_state}
  end

  def handle_call({:close_chan, chan}, _from, state) do
    :ok = AMQP.Channel.close(chan)
    {:reply, :ok, state}
  end

  def handle_call({:publish, exchange, payload, chan_name, opts}, _from, %{chans: chans} = state)
      when is_binary(chan_name) or is_atom(chan_name) do
    chan = chans[chan_name]

    AMQP.Basic.publish(chan, "", exchange, payload, opts)
    {:reply, :ok, state}
  end

  def handle_call({:publish, exchange, payload, chan, opts}, _from, state) do
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
      )
      when is_binary(chan_name) or is_atom(chan_name) do
    chan = chans[chan_name]

    do_request(
      exchange,
      payload,
      chan,
      pid_from,
      state,
      opts
    )
  end

  def handle_call(
        {:request, exchange, payload, chan, opts},
        {pid_from, _},
        state
      ) do
    do_request(
      exchange,
      payload,
      chan,
      pid_from,
      state,
      opts
    )
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
            [pid_from | subscribers]

          _ ->
            subscribers
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

  def terminate(reason, %{conn_name: conn_name, subscriptions: subscriptions} = state) do
    Logger.info("Closing AMQP Connection reason: #{inspect(reason)}")

    if conn_name != nil do
      if reason in [:normal, :shutdown] or match?({:shutdown, _}, reason) do
        :ets.delete(:conns, conn_name)
      else
        pids =
          subscriptions
          |> Enum.flat_map(fn {_k, v} -> v end)
          |> Enum.uniq()

        :ets.insert(:conns, {conn_name, pids})
      end
    end

    %AMQP.Connection{pid: pid} = state.conn

    if Process.alive?(pid) do
      AMQP.Connection.close(state.conn)
    end

    :ok
  end

  @spec consume(pid, struct, String.t()) :: String.t()
  defp consume(pid, chan, exchange) do
    {:ok, %{queue: queue_name}} = AMQP.Queue.declare(chan, exchange, durable: false)
    {:ok, _} = AMQP.Basic.consume(chan, queue_name, pid, no_ack: true)
    queue_name
  end

  defp do_request(
         exchange,
         payload,
         chan,
         pid_from,
         state,
         opts
       ) do
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
end
