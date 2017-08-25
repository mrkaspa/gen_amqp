# GenAmqp

GenAMQP is a set of utilities to make microservices using the worker pattern, where you can have many workers listening on a queue and they can execute this in a synchronous or asynchronous.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

Add `gen_amqp` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:gen_amqp, "~> 2.0.0"}]
  end

  def application do
    [applications: [:gen_amqp]]
  end
  ```
