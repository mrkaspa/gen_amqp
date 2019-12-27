defmodule GenAMQP.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gen_amqp,
      version: "6.0.0",
      elixir: ">= 1.8.0",
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
      [extra_applications: [:logger], mod: {DemoApp, []}]
    else
      [extra_applications: [:logger], mod: {GenAMQP, []}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:amqp, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, "~> 0.21.2", only: :dev},
      {:poison, "~> 4.0", only: :test},
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
