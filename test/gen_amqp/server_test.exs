defmodule GenAMQP.ServerTest do
  use ExUnit.Case

  test "should be alive" do
    assert Elixir.ServerDemo |> Process.whereis() |> Process.alive?() == true
  end
end
