defmodule GenAMQP.Server do
  @moduledoc """
  Defines the behaviour for servers connected through RabbitMQ
  """

  defmacro __using__(opts) do
    event = opts[:event]
    size = Keyword.get(opts, :size, 3)
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
        children =
          Enum.map(1..unquote(size), fn num ->
            id = :"#{__MODULE__.Worker}_#{num}"
            worker(__MODULE__.Worker, [id], id: id, restart: :transient, shutdown: 1)
          end)

        Logger.info("Starting #{__MODULE__}")
        supervise(children, strategy: :one_for_one)
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

        def start_link(name) do
          GenServer.start_link(__MODULE__, [name], name: name)
        end

        def init([name]) do
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
             conn_created: conn_created
           }}
        end

        defp start_conn(server_name, nil) do
          conn_name = String.to_atom("#{server_name}.Conn")
          spec = {GenAMQP.Conn, conn_name}
          {:ok, conn_pid} = DynamicSupervisor.start_child(unquote(dynamic_sup_name), spec)
          {conn_name, conn_pid, true}
        end

        defp start_conn(_server_name, conn_name) do
          conn_pid = Process.whereis(conn_name)
          {conn_name, conn_pid, false}
        end

        defp reduce_with_funcs(funcs, event, payload) do
          Enum.reduce(funcs, payload, fn f, acc ->
            f.(event, acc)
          end)
        end

        def on_message(payload, meta, %{conn_name: conn_name, chan_name: chan_name} = state) do
          payload = reduce_with_funcs(unquote(before_funcs), unquote(event), payload)

          {reply?, resp} =
            try do
              case apply(@exec_module, :execute, [payload]) do
                {:reply, resp} ->
                  {true, resp}

                :noreply ->
                  {false, nil}

                other ->
                  case apply(@exec_module, :handle, [other]) do
                    {:reply, resp} ->
                      {true, resp}

                    :noreply ->
                      {false, nil}
                  end
              end
            rescue
              e ->
                Logger.error("STACKTRACE - RESCUE")
                st = inspect(System.stacktrace())
                Logger.error(st)

                case create_error({inspect(e), st}) do
                  {:reply, resp} ->
                    {true, resp}

                  :noreply ->
                    {false, nil}
                end
            catch
              :exit, reason ->
                Logger.error("STACKTRACE - EXIT")
                st = inspect(System.stacktrace())
                Logger.error(st)

                case create_error({reason, st}) do
                  {:reply, resp} ->
                    {true, resp}

                  :noreply ->
                    {false, nil}
                end
            end

          resp = reduce_with_funcs(unquote(after_funcs), unquote(event), resp)

          if reply? do
            reply(conn_name, chan_name, meta, resp)
          end
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

        defp reply(
               _conn_name,
               _chan_name,
               %{reply_to: :undefined, correlation_id: :undefined} = meta,
               resp
             ),
             do: nil

        defp reply(conn_name, chan_name, %{reply_to: _, correlation_id: _} = meta, resp)
             when is_binary(resp) do
          Conn.response(conn_name, meta, resp, chan_name)
        end

        defp reply(conn_name, chan_name, %{reply_to: _, correlation_id: _} = meta, resp) do
          Logger.error("message in wrong type #{inspect(resp)}")
          Conn.response(conn_name, meta, create_error("message in wrong type"), chan_name)
        end

        defp create_error(msg) do
          module = Application.get_env(:gen_amqp, :error_handler)
          sol = apply(module, :handle, [msg])
          IO.puts("SOL = #{inspect(sol)}")
          apply(module, :handle, [msg])
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
