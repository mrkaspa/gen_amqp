# GenAMQP Microservices Utilities

GenAMQP is a set of utilities to make microservices sync or async over RabbitMQ

## Installation

If [available in Hex](https://hex.pm/packages/gen_amqp), the package can be installed as:

Add `gen_amqp` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:gen_amqp, "~> 7.0.0"}]
  end

  def application do
    [applications: [:gen_amqp]]
  end
  ```
