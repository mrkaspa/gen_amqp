defmodule GenAMQP.ServerTest do
  use ExUnit.Case
  use GenDebug

  test "should be alive" do
    assert Elixir.ServerDemo |> Process.whereis() |> Process.alive?() == true
  end

  test "the static connection should have one channel" do
    conn_name = ConnHub
    chans = state(conn_name)[:chans]
    assert Enum.count(chans) == 10
    assert chans[ServerDemo.Worker_1] != nil
  end

  test "count the childrens connections" do
    static_sup_name = StaticConnSup
    dynamic_sup_name = DynamicConnSup
    assert Supervisor.count_children(static_sup_name).active == 1
    assert Supervisor.count_children(dynamic_sup_name).active == 6
  end
end
