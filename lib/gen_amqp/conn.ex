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
  @spec start_link(String.t(), GenServer.name()) :: GenServer.on_start()
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

  @spec add_subscription(GenServer.name(), pid()) :: :ok
  def add_subscription(name, pid) do
    GenServer.cast(name, {:add_subscription, pid})
  end

  @spec remove_subscription(GenServer.name(), pid()) :: :ok
  def remove_subscription(name, pid) do
    GenServer.cast(name, {:remove_subscription, pid})
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

    {:ok, %{conn: conn, conn_name: name, chans: %{default: chan}, subscriptions: []}}
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
      {:reply, resp, new_state}
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

  def handle_cast({:add_subscription, pid}, %{subscriptions: subscriptions} = state) do
    {:noreply, %{state | subscriptions: [pid | subscriptions]}}
  end

  def handle_cast({:remove_subscription, pid}, %{subscriptions: subscriptions} = state) do
    {:noreply, %{state | subscriptions: List.delete(subscriptions, pid)}}
  end

  def terminate(reason, %{conn_name: conn_name, subscriptions: subscriptions} = state) do
    Logger.info("Closing AMQP Connection reason: #{inspect(reason)}")

    if conn_name != nil do
      if reason in [:normal, :shutdown] or match?({:shutdown, _}, reason) do
        :ets.delete(:conns, conn_name)
      else
        IO.inspect(subscriptions, label: "subscriptions")

        pids =
          subscriptions
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
end
