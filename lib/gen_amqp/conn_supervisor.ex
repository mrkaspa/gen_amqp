defmodule GenAMQP.ConnSupervisor do
  @moduledoc """
  Main app
  """

  use Supervisor
  require Logger

  def start_link(sup_name, conn_name \\ nil) do
    Logger.info("Starting Supervisor: #{sup_name}")
    Supervisor.start_link(__MODULE__, [conn_name], name: sup_name)
  end

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def init([conn_name]) do
    set_strategy(conn_name)
  end

  defp set_strategy(nil) do
    Logger.info("With dynamic")

    children = [
      worker(GenAMQP.Conn, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  defp set_strategy(conn_name) do
    Logger.info("With static")

    children = [
      worker(GenAMQP.Conn, [conn_name], restart: :transient)
    ]

    supervise(children, strategy: :one_for_one)
  end
end
