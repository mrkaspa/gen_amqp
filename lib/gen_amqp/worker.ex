defmodule GenAMQP.PoolWorker do
  alias GenAMQP.Conn
  require Logger

  def work(%{
        event: event,
        exec_module: exec_module,
        before_funcs: before_funcs,
        after_funcs: after_funcs,
        conn_name: conn_name,
        chan_name: chan_name,
        payload: payload,
        meta: meta
      }) do
    Logger.info("Message Ack (#{inspect(self())}): -> #{meta.delivery_tag} \n content #{payload}")

    :ok = Conn.ack(conn_name, chan_name, meta)

    payload = reduce_with_funcs(before_funcs, event, payload)

    {reply?, resp} =
      try do
        case apply(exec_module, :execute, [payload]) do
          {:reply, resp} ->
            {true, resp}

          :noreply ->
            {false, nil}

          other ->
            case apply(exec_module, :handle, [other]) do
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

    resp = reduce_with_funcs(after_funcs, event, resp)

    if reply? do
      reply(conn_name, chan_name, meta, resp)
    end
  end

  defp reply(
         _conn_name,
         _chan_name,
         %{reply_to: :undefined, correlation_id: :undefined},
         _resp
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

  defp reduce_with_funcs(funcs, event, payload) do
    Enum.reduce(funcs, payload, fn f, acc ->
      f.(event, acc)
    end)
  end
end
