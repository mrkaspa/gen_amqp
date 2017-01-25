defmodule GenAMQP.ClientTest do
  use ExUnit.Case
  alias GenAMQP.Client

  test "get a response" do
    assert Client.call("demo", "") == "ok"
  end

  test "it crashes" do
    resp = Client.call("crash", "")
    data = Poison.decode!(resp)
    assert data["status"] == "error"
  end
end
