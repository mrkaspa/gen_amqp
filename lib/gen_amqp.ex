defmodule GenAMQP do
  @moduledoc false

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
