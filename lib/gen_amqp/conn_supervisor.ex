defmodule GenAMQP.ConnSupervisor do
  @moduledoc """
  Main app
  """

  require Logger
  alias GenAMQP.ConnSupervisor.{Static, Dynamic}

  def start_link(sup_name, nil, conn_url) do
    Logger.info("Starting Supervisor: #{sup_name}")
    DynamicSupervisor.start_link(Dynamic, conn_url, name: sup_name)
  end

  def start_link(sup_name, conn_name, conn_url) do
    Logger.info("Starting Supervisor: #{sup_name}")
    Supervisor.start_link(Static, [conn_name, conn_url], name: sup_name)
  end

  defmodule Static do
    use Supervisor

    def init([conn_name, conn_url]) do
      Logger.info("With static")
      :ets.new(:conns, [:named_table, :set, :public])

      children = [
        worker(GenAMQP.Conn, [conn_url, conn_name], restart: :transient)
      ]

      supervise(children, strategy: :one_for_one)
    end
  end

  defmodule Dynamic do
    use DynamicSupervisor

    @impl true
    def init(conn_url) do
      DynamicSupervisor.init(
        strategy: :one_for_one,
        extra_arguments: [conn_url]
      )
    end
  end
end
