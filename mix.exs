defmodule GenAMQP.Mixfile do
  use Mix.Project

  def project do
    [app: :gen_amqp,
     version: "0.3.1",
     elixir: "~> 1.3",
     description: description(),
     package: package(),
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env() == :prod,
     start_permanent: Mix.env() == :prod,
     deps: deps(),
     test_coverage: [tool: ExCoveralls]]
  end

  defp description do
    """
    GenAMQP is a set of utilities to make microservices using the worker pattern
    """
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    if Mix.env() == :test do
      [applications: [:logger, :amqp], mod: {DemoApp, []}]
    else
      [applications: [:logger, :amqp], mod: {GenAMQP, []}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:amqp, "~> 0.1.5"},
      {:amqp_client, git: "https://github.com/jbrisbin/amqp_client.git", tag: "rabbitmq-3.6.2", override: true},
      {:rabbit_common, "~> 3.6.7-pre.1", override: true},
      {:poison, "~> 2.0"},
      {:ex_doc, "~> 0.12", only: :doc},
      {:dialyxir, "~> 0.4.1", only: :dev},
      {:credo, github: "rrrene/credo", only: :dev},
      {:ex_doc, "~> 0.14.5", only: :dev},
      {:excoveralls, "~> 0.5", only: :test}
    ]
  end

  defp package do
    [# These are the default files included in the package
      name: :gen_amqp,
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Michel Perez"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/mrkaspa/gen_amqp"}
    ]
  end
end
