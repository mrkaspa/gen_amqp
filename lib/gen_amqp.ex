defmodule GenAMQP do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define supervisors and child supervisors to be supervised
    children = [
      supervisor(GenAMQP.Supervisor, []),
    ]

    opts = [strategy: :one_for_one, name: GenAMQP.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
