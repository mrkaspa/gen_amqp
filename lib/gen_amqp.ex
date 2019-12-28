defmodule GenAMQP do
  @moduledoc """
  GenAMQP is a library to create easily Publish/Subscribe and RPC style in AMQP by defining some settings and using a friendly macro

  In the settings file put:

  ```elixir
      config :gen_amqp,
        connections: [
          {:static, StaticConnSup, [ConnHub: "amqp://guest:guest@localhost"]}
        ],
        error_handler: ErrorHandler
  ```

  The error handler must handle a failure structure that can be any

  ```elixir
      defmodule ErrorHandler do
        def handle(msg) do
          Poison.encode!(%{
            status: :error,
            code: 0,
            message: msg
          })
        end
      end
  ```

  The ServerDemo here uses the GenAMQP.Server and implements two functions, execute and handle. The execute function receives the incoming payload in string format and must return the tuple {:reply, content} where content is the response that will be returned in amqp or no reply if you don't need to response. The handle function handles the cases not matched in the execute function.

  ```elixir
      defmodule ServerDemo do
        @moduledoc false

        use GenAMQP.Server, event: "server_demo", conn_name: Application.get_env(:gen_amqp, :conn_name)

        def execute(payload) do
          with {:ok, _} <- {:error, "error"} do
            {:reply, "ok"}
          end
        end

         def handle({:error, cause}) do
          {:reply, cause}
        end
      end
  ```

  In the systems there is a supervisor for the connection that can be dynamic or static, if it's static supervises one connection, if it's dynamic creates a new supervised connection for each client

  """

  use Application

  def start(_type, _args) do
    conns = Application.get_env(:gen_amqp, :connections)
    specs = conns_to_specs(conns)

    # Define supervisors and child supervisors to be supervised
    children = specs

    opts = [strategy: :one_for_one, name: GenAMQP.AppSupervisor]
    Supervisor.start_link(children, opts)
  end

  defp conns_to_specs(conns) do
    import Supervisor.Spec, warn: false

    Enum.map(conns, fn
      {:static, sup_name, conns} ->
        supervisor(GenAMQP.ConnSupervisor, [sup_name, conns], id: sup_name)
    end)
  end
end
