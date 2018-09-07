defmodule GenAMQP.ServerTest do
  use ExUnit.Case
  use GenDebug

  test "should be alive" do
    assert Elixir.ServerDemo |> Process.whereis() |> Process.alive?() == true
  end

  test "the static connection should have one channel" do
    conn_name = ConnHub
    chans = state(conn_name)[:chans]
    assert Enum.count(chans) == 13
    assert chans[ServerDemo.Worker_1] != nil
  end

  test "count the childrens connections" do
    static_sup_name = StaticConnSup
    assert Supervisor.count_children(static_sup_name).active == 1
  end
end
