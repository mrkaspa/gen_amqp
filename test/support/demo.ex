defmodule ErrorHandler do
  def handle(msg) do
    Poison.encode!(%{
      status: :error,
      code: 0,
      message: msg
    })
  end
end

defmodule ServerDemo do
  @moduledoc false

  use GenAMQP.Server, event: "server_demo", conn_name: Application.get_env(:gen_amqp, :conn_name)

  def execute(_) do
    {:reply, "ok"}
  end
end

defmodule DynamicServerDemo do
  @moduledoc false

  use GenAMQP.Server, event: "dyna", conn_supervisor: Application.get_env(:gen_amqp, :dynamic_sup_name)

  def execute(_) do
    {:reply, "ok"}
  end
end

defmodule ServerCrash do
  @moduledoc false

  use GenAMQP.Server, event: "crash", conn_supervisor: Application.get_env(:gen_amqp, :dynamic_sup_name)

  def execute(_) do
    raise "error"
  end
end

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
      supervisor(DynamicServerDemo, []),
      supervisor(ServerCrash, []),
    ]

    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
