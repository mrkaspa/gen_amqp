defmodule GenAMQP do
  @moduledoc """
  GenAMQP is a library to create easily Publish/Subscribe and RPC style in AMQP by defining some settings and using a friendly macro

  In the settings file put:

  ```elixir
      config :gen_amqp,
        amqp_url: "amqp://guest:guest@localhost",
        conn_name: ConnHub,
        static_sup_name: StaticConnSup,
        dynamic_sup_name: DynamicConnSup,
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

  ```elixir
      defmodule DemoApp do
        @moduledoc false

        use Application

        def start(_type, _args) do
          import Supervisor.Spec, warn: false

          conn_name = Application.get_env(:gen_amqp, :conn_name)
          static_sup_name = Application.get_env(:gen_amqp, :static_sup_name)
          dynamic_sup_name = Application.get_env(:gen_amqp, :dynamic_sup_name)

          # Define supervisors and child supervisors to be supervised
          children = [
            supervisor(GenAMQP.ConnSupervisor, [static_sup_name, conn_name], [id: static_sup_name]),
            supervisor(GenAMQP.ConnSupervisor, [dynamic_sup_name], id: dynamic_sup_name),
            supervisor(ServerDemo, []),
          ]

          opts = [strategy: :one_for_one, name: Core.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
  ```


  """

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    conn_name = Application.get_env(:gen_amqp, :conn_name)
    static_sup_name = Application.get_env(:gen_amqp, :static_sup_name)
    dynamic_sup_name = Application.get_env(:gen_amqp, :dynamic_sup_name)

    sup_name = static_sup_name || dynamic_sup_name

    # Define supervisors and child supervisors to be supervised
    children = [
      supervisor(GenAMQP.ConnSupervisor, [sup_name, conn_name]),
    ]

    opts = [strategy: :one_for_one, name: GenAMQP.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
