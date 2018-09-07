defmodule GenAMQP.ConnSupervisor do
  @moduledoc """
  Main app
  """

  require Logger
  use Supervisor

  def start_link(sup_name, conn_name, conn_url) do
    Logger.info("Starting Supervisor: #{sup_name}")
    Supervisor.start_link(__MODULE__, [conn_name, conn_url], name: sup_name)
  end

  def init([conn_name, conn_url]) do
    Logger.info("With static")
    :ets.new(:conns, [:named_table, :set, :public])

    children = [
      worker(GenAMQP.Conn, [conn_url, conn_name], restart: :transient)
    ]

    supervise(children, strategy: :one_for_one)
  end
end
