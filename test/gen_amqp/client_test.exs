defmodule GenAMQP.ClientTest do
  use ExUnit.Case
  alias GenAMQP.Client

  @conn_name ConnHub

  describe "server with handle" do
    test "get a response" do
      assert Client.call_with_conn(@conn_name, "server_handle_demo", "", max_time: 10_000) ==
               "error"
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

    test "get a response with app_id option" do
      assert Client.call_with_conn(
               @conn_name,
               "server_demo",
               "",
               max_time: 10_000,
               app_id: "v1.0"
             ) == "ok"
    end

    test "publish a message with app_id option" do
      Client.publish_with_conn(@conn_name, "server_demo", "", app_id: "v1.0")
    end
  end

  describe "with before and after" do
    test "calls the server" do
      Agent.start(fn -> 0 end, name: Agt)
      assert Client.call_with_conn(@conn_name, "server_callback_demo", "", app_id: "v1.0") == "ok"
      assert Agent.get(Agt, & &1) == 2
      Agent.stop(Agt)
    end
  end
end
