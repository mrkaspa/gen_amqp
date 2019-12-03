defmodule ErrorHandler do
  def handle(kind, reason, stacktrace) do
    handle(Exception.normalize(kind, reason, stacktrace), stacktrace)
  end

  def handle(error, _stacktrace) do
    resp =
      Poison.encode!(%{
        status: :error,
        code: 0,
        message: inspect(error)
      })

    {:reply, resp}
  end
end

defmodule ServerDemo do
  @moduledoc false

  use GenAMQP.Server, event: "server_demo", conn_name: ConnHub

  @impl true
  def execute(_params, _ctx) do
    {:reply, "ok"}
  end
end

defmodule ServerWithDelay do
  @moduledoc false

  use GenAMQP.Server, event: "server_delay", conn_name: ConnHub, size: 1

  @impl true
  def execute(_params, _ctx) do
    Process.sleep(2000)
    {:reply, "ok"}
  end
end

defmodule ServerWithCallbacks do
  @moduledoc false

  use GenAMQP.Server,
    event: "server_callback_demo",
    conn_name: ConnHub,
    before: [
      fn payload, ctx ->
        Agent.update(Agt, fn n -> n + 1 end)
        [payload, ctx]
      end
    ],
    after: [
      fn payload, ctx ->
        Agent.update(Agt, fn n -> n + 1 end)
        [payload, ctx]
      end
    ]

  @impl true
  def execute(_params, _ctx) do
    {:reply, "ok"}
  end
end

defmodule ServerCrash do
  @moduledoc false

  use GenAMQP.Server,
    event: "crash",
    conn_name: ConnHub

  @impl true
  def execute(_params, _ctx) do
    raise "error"
  end
end

defmodule DemoApp do
  @moduledoc false

  use Application
  import Supervisor.Spec, warn: false

  def start(_type, _args) do
    conns = Application.get_env(:gen_amqp, :connections)
    specs = conns_to_specs(conns)

    # Define supervisors and child supervisors to be supervised
    children =
      specs ++
        [
          supervisor(ServerDemo, []),
          supervisor(ServerWithCallbacks, []),
          supervisor(ServerWithDelay, []),
          supervisor(ServerCrash, [])
        ]

    opts = [strategy: :one_for_one, name: GenAMQP.AppSupervisor]
    Supervisor.start_link(children, opts)
  end

  defp conns_to_specs(conns) do
    Enum.map(conns, fn
      {:static, sup_name, conns} ->
        supervisor(GenAMQP.ConnSupervisor, [sup_name, conns], id: sup_name)
    end)
  end
end
