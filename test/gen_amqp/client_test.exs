defmodule GenAMQP.ClientTest do
  use ExUnit.Case
  alias GenAMQP.Client

  test "get a response" do
    assert Client.call("demo", "") == "ok"
  end
end
