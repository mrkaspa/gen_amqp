defmodule GenAMQP.Server do
  @moduledoc """
  Defines the behaviour for servers connected through RabbitMQ
  """

  defmacro __using__(opts) do
    event = opts[:event]
    conn_name = Keyword.get(opts, :conn_name, nil)
    dynamic_sup_name = Keyword.get(opts, :conn_supervisor, nil)
    before_funcs = Keyword.get(opts, :before, [])
    after_funcs = Keyword.get(opts, :after, [])

    quote do
      require Logger
      use Supervisor

      @behaviour GenAMQP.Server.Behaviour

      # Default callbacks implementations

      def handle(data) do
        Logger.warn(
          "Not handling #{inspect(data)} in #{__MODULE__}, please declare a handle function"
        )

        :noreply
      end

      defoverridable handle: 1

      # Public API

      def start_link() do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        name = __MODULE__.Worker
        pool_name = __MODULE__.Pool
        sup_name = __MODULE__.Supervisor
        poolboy_config =  [
          {:name, {:local, pool_name}},
          {:worker_module, GenAMQP.PoolWorker},
          {:size, 10},
          {:max_overflow, 5}
        ]
        children = [
          :poolboy.child_spec(pool_name, poolboy_config),
          worker(name, [name, pool_name], id: name, restart: :transient)
        ]

        Logger.info("Starting #{__MODULE__}")
        supervise(children, strategy: :one_for_one, name: sup_name)
      end

      def reply(msg), do: {:reply, msg}

      def noreply(), do: :noreply

      defmodule Worker do
        use GenServer
        alias GenAMQP.Conn

        @exec_module __MODULE__
                     |> Atom.to_string()
                     |> String.split(".")
                     |> (fn enum ->
                           size = length(enum)
                           List.delete_at(enum, size - 1)
                         end).()
                     |> Enum.join(".")
                     |> String.to_atom()

        def start_link(name, pool_name) do
          GenServer.start_link(__MODULE__, [name, pool_name], name: name)
        end

        def init([name, pool_name]) do
          Logger.info("Starting #{name}")

          chan_name = name
          Logger.info("Creating server #{name} with chan #{chan_name}")

          {conn_name, conn_pid, conn_created} = start_conn(name, unquote(conn_name))

          :ok = Conn.create_chan(conn_name, chan_name)
          :ok = Conn.subscribe(conn_name, unquote(event), chan_name)

          {:ok,
           %{
             consumer_tag: nil,
             conn_name: conn_name,
             conn_pid: conn_pid,
             chan_name: chan_name,
             conn_created: conn_created,
             pool_name: pool_name
           }}
        end

        defp start_conn(_server_name, conn_name) do
          conn_pid = Process.whereis(conn_name)
          {conn_name, conn_pid, false}
        end

        def on_message(payload, meta, %{conn_name: conn_name, chan_name: chan_name, pool_name: pool_name} = state) do

          data = %{
            event: unquote(event),
            exec_module: @exec_module,
            before_funcs: unquote(before_funcs),
            after_funcs: unquote(after_funcs),
            conn_name: conn_name,
            chan_name: chan_name,
            payload: payload,
            meta: meta
          }

          Task.async(fn ->
            :poolboy.transaction(
              pool_name,
              fn pid -> GenServer.call(pid, {:do_work, data}) end
            )
          end)
        end

        def handle_cast(:reconnect, %{conn_name: conn_name, chan_name: chan_name} = state) do
          Logger.info("Server #{chan_name} reconnecting to #{conn_name}")
          :ok = Conn.create_chan(conn_name, chan_name)
          :ok = Conn.subscribe(conn_name, unquote(event), chan_name)
          {:noreply, state}
        end

        def handle_info({:basic_deliver, payload, meta}, state) do
          on_message(payload, meta, state)
          {:noreply, state}
        end

        def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
          {:noreply, %{state | consumer_tag: consumer_tag}}
        end

        def handle_info(message, state) do
          Logger.info("Unhandle message in #{__MODULE__} = #{inspect(message)}")
          {:noreply, state}
        end

        def terminate(reason, %{conn_pid: conn_pid, conn_created: true} = _state) do
          :ok = Supervisor.terminate_child(unquote(dynamic_sup_name), conn_pid)
          Logger.error("Terminate connection in #{__MODULE__}, reason: #{inspect(reason)}")
        end

        def terminate(
              reason,
              %{conn_name: conn_name, chan_name: chan_name, conn_created: false} = _state
            ) do
          :ok = Conn.close_chan(conn_name, chan_name)

          Logger.error(
            "Terminate channel #{chan_name} in #{__MODULE__}, reason: #{inspect(reason)}"
          )
        end
      end
    end
  end

  defmodule Behaviour do
    @moduledoc """
    Behaviour to implement by the servers
    """

    @callback execute(any()) :: {:reply, any()} | :noreply

    @callback handle(any()) :: {:reply, any()} | :noreply
  end
end
