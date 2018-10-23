defmodule GenAMQP.ConnTest do
  use ExUnit.Case
  alias GenAMQP.{Conn, Chan}
  use GenDebug

  setup_all do
    {:ok, counter_pid} = Agent.start(fn -> 0 end)
    {:ok, counter: counter_pid}
  end

  setup %{counter: counter_pid} do
    counter_name =
      "test_#{Agent.get_and_update(counter_pid, fn state -> {state, state + 1} end)}"
      |> String.to_atom()

    {:ok, pid} =
      Conn.start_link(
        System.get_env("RABBITCONN") || "amqp://guest:guest@localhost",
        counter_name
      )

    {:ok, pid: pid}
  end

  test "should be alive", %{pid: pid} do
    assert Process.alive?(pid) == true
  end

  test "should terminate the conn", %{pid: pid} do
    assert Process.exit(pid, :die) == true
  end

  test "should create and delete a channel", %{pid: pid} do
    {:ok, _} = Conn.create_chan(pid, :demo)
    chans = state(pid)[:chans]
    assert Enum.count(chans) == 2

    :ok = Conn.close_chan(pid, :demo)
    chans = state(pid)[:chans]
    assert Enum.count(chans) == 1
  end

  test "should publish", %{pid: pid} do
    {:ok, chan} = Conn.create_chan(pid, :demo)
    assert Chan.publish(chan, "", "encrypt", "demo") == :ok
  end

  test "should subscribe", %{pid: pid} do
    {:ok, chan} = Conn.create_chan(pid, :demo)
    assert Chan.subscribe(pid, chan, "encrypt", self()) == :ok
    Chan.publish(chan, "", "encrypt", "demo")
    assert_receive {:basic_deliver, "demo", _}
  end

  test "should unsubscribe", %{pid: pid} do
    {:ok, chan} = Conn.create_chan(pid, :demo)
    assert Chan.subscribe(pid, chan, "encrypt", self()) == :ok
    assert Chan.unsubscribe(pid, chan, "encrypt", :demo) == :ok
    Chan.publish(chan, "", "encrypt", "demo")
    refute_receive {:basic_deliver, "demo", _}
  end

  describe "with a managed connection" do
    test "should keep the channels after death" do
      chans = state(ConnHub)[:chans]
      assert Enum.count(chans) == 6

      ConnHub
      |> Process.whereis()
      |> Process.exit(:die)

      Process.sleep(1000)
      assert Process.whereis(ConnHub) |> Process.alive?()
      chans = state(ConnHub)[:chans]
      assert Enum.count(chans) == 6
    end
  end
end
