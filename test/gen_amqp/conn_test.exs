defmodule GenAMQP.ConnTest do
  use ExUnit.Case
  alias GenAMQP.Conn

  setup do
    {:ok, pid} = GenAMQP.Conn.start_link()
    {:ok, pid: pid}
  end

  test "should be alive", %{pid: pid} do
    assert Process.alive?(pid) == true
  end

  test "should terminate the conn", %{pid: pid} do
    assert Process.exit(pid, :kill) == true
  end

  test "should publish", %{pid: pid} do
    assert Conn.publish(pid, "encrypt", "demo") == :ok
  end

  test "should subscribe", %{pid: pid} do
    assert Conn.subscribe(pid, "encrypt") == :ok
    Conn.publish(pid, "encrypt", "demo")
    assert_receive {:basic_deliver, "demo", _}
  end

  test "should unsubscribe", %{pid: pid} do
    Conn.subscribe(pid, "encrypt")
    assert Conn.unsubscribe(pid, "encrypt") == :ok
    Conn.publish(pid, "encrypt", "demo")
    refute_receive {:basic_deliver, "demo", _}
  end
end
