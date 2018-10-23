defmodule GenAMQP.ConnSupervisor do
  @moduledoc """
  Main app
  """

  require Logger
  use Supervisor

  def start_link(sup_name, conns) do
    Logger.info("Starting Supervisor: #{sup_name}")
    Supervisor.start_link(__MODULE__, [conns], name: sup_name)
  end

  def init([conns]) do
    Logger.info("With static")
    :ets.new(:conns, [:named_table, :set, :public])

    children =
      Enum.map(conns, fn {conn_name, conn_url} ->
        worker(GenAMQP.Conn, [conn_url, conn_name], restart: :transient, id: conn_name)
      end)

    supervise(children, strategy: :one_for_one, max_restarts: 10)
  end
end
