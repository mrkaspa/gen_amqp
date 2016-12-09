# GenAmqp

GenAMQP is a set of utilities to make microservices using the worker pattern

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `gen_amqp` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:gen_amqp, "~> 0.1.2"}]
    end
    ```

  2. Add the connection url to the config.exs

    ```elixir
    config :gen_amqp, GenAMQP.Conn,
      amqp_url: System.get_env("RABBITCONN") || "amqp://@localhost"
    ```

  3. Create a module and configure it:

    ```elixir
    defmodule ServerDemo do
      @moduledoc false

      use GenAMQP.Server, event: "demo"

      def execute(_) do
        {:reply, "ok"}
      end
    end
    ```

  4. Add it to the app:

    ```elixir
    defmodule DemoApp do
      @moduledoc false

      use Application

      def start(_type, _args) do
        import Supervisor.Spec, warn: false

        # Define supervisors and child supervisors to be supervised
        children = [
          supervisor(ServerDemo, []),
        ]

        opts = [strategy: :one_for_one, name: Core.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end
    ```
