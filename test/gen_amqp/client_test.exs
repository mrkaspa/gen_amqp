defmodule GenAMQP.ClientTest do
  use ExUnit.Case
  alias GenAMQP.Client

  @conn_name Application.get_env(:gen_amqp, :conn_name)
  @dynamic_sup_name Application.get_env(:gen_amqp, :dynamic_sup_name)

  describe "with dynamic conn" do
    test "get a response" do
      assert Client.call(@dynamic_sup_name, "server_demo", "", max_time: 10_000) == "ok"
    end

    test "it crashes" do
      resp = Client.call(@dynamic_sup_name, "crash", "")
      data = Poison.decode!(resp)
      assert data["status"] == "error"
    end

    test "publish a message" do
      Client.publish(@dynamic_sup_name, "server_demo", "")
    end
  end

  describe "with static conn" do
    test "get a response" do
      assert Client.call_with_conn(@conn_name, "server_demo", "") == "ok"
    end

    test "it crashes" do
      resp = Client.call_with_conn(@conn_name, "crash", "")
      data = Poison.decode!(resp)
      assert data["status"] == "error"
    end

    test "publish a message" do
      Client.publish_with_conn(@conn_name, "server_demo", "")
    end
  end
end
