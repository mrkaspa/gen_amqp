defmodule GenAMQP.PoolWorker do
  alias GenAMQP.Chan
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, [])
  end

  def init(_) do
    {:ok, nil}
  end

  def handle_call({:do_work, data}, _from, state) do
    work(data)
    {:reply, nil, state}
  end

  defp work(%{
         event: event,
         exec_module: exec_module,
         before_funcs: before_funcs,
         after_funcs: after_funcs,
         chan: chan,
         payload: payload,
         meta: meta
       }) do
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
          st = System.stacktrace()
          Logger.error("EXCEPTION: #{Exception.message(e)}")
          Logger.error(inspect(st))

          case create_error([e, st]) do
            {:reply, resp} ->
              {true, resp}

            :noreply ->
              {false, nil}
          end
      catch
        kind, reason ->
          Logger.error("STACKTRACE - EXIT")
          st = System.stacktrace()
          Logger.error(inspect(st))

          case create_error([kind, reason, st]) do
            {:reply, resp} ->
              {true, resp}

            :noreply ->
              {false, nil}
          end
      end

    resp = reduce_with_funcs(after_funcs, event, resp)

    if reply? do
      reply(chan, meta, resp)
    end
  end

  defp reply(
         _chan,
         %{reply_to: :undefined, correlation_id: :undefined},
         _resp
       ),
       do: nil

  defp reply(chan, %{reply_to: _, correlation_id: _} = meta, resp)
       when is_binary(resp) do
    Chan.response(chan, meta, resp)
  end

  defp reply(chan, %{reply_to: _, correlation_id: _} = meta, resp) do
    Logger.error("message in wrong type #{inspect(resp)}")
    Chan.response(chan, meta, create_error("message in wrong type"))
  end

  defp create_error(args) do
    module = Application.get_env(:gen_amqp, :error_handler)
    sol = apply(module, :handle, args)
    IO.puts("SOL = #{inspect(sol)}")
    sol
  end

  defp reduce_with_funcs(funcs, event, payload) do
    Enum.reduce(funcs, payload, fn f, acc ->
      f.(event, acc)
    end)
  end
end
