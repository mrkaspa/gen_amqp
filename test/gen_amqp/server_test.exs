defmodule GenAMQP.ServerTest do
  use ExUnit.Case
  use GenDebug

  test "should be alive" do
    assert Elixir.ServerDemo |> Process.whereis() |> Process.alive?() == true
  end

  test "the static connection should have one channel" do
    conn_name = Application.get_env(:gen_amqp, :conn_name)
    chans = state(conn_name)[:chans]
    assert Enum.count(chans) == 4
    assert chans[ServerDemo.Worker_1] != nil
  end

  test "count the childrens connections" do
    static_sup_name = Application.get_env(:gen_amqp, :static_sup_name)
    dynamic_sup_name = Application.get_env(:gen_amqp, :dynamic_sup_name)
    assert Supervisor.count_children(static_sup_name).active == 1
    assert Supervisor.count_children(dynamic_sup_name).active == 6
  end
end
