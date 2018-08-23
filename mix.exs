defmodule GenAMQP.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gen_amqp,
      version: "3.5.0",
      elixir: "~> 1.6.0",
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  defp description do
    """
    GenAMQP is a set of utilities to make microservices using the worker pattern
    """
  end

  def application do
    if Mix.env() == :test do
      [applications: [:logger, :amqp], mod: {DemoApp, []}]
    else
      [applications: [:logger, :amqp], mod: {GenAMQP, []}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:amqp, "~> 1.0.3"},
      {:uuid, "~> 1.1.1"},
      {:dialyxir, "~> 0.5", only: :dev},
      {:credo, "~> 0.10", only: :dev},
      {:ex_doc, "~> 0.18.4", only: :dev},
      {:poison, "~> 3.0", only: :test},
      {:excoveralls, "~> 0.9", only: :test},
      {:gen_debug, "~> 0.2.0", only: :test}
    ]
  end

  defp package do
    # These are the default files included in the package
    [
      name: :gen_amqp,
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Michel Perez"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/mrkaspa/gen_amqp"}
    ]
  end
end
