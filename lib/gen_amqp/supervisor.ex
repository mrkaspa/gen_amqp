defmodule GenAMQP.Supervisor do
  @moduledoc """
  Main app
  """

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def init(_) do
    # Define workers and child supervisors to be supervised
    children = [
      worker(GenAMQP.Conn, [], restart: :transient, shutdown: 1)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
