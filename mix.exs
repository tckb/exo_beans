defmodule ExoBeans.MixProject do
  use Mix.Project

  def project do
    [
      aliases: aliases(),
      # app related details
      app: :exo_beans,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # P-ersistent L-ookup T-able  is a compile cache containing the analysis of your app -- helps in speeding up dialyxir
      dialyzer: [ignore_warnings: "dialyzer.ignore-warnings"],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExoBeans.Application, []}
    ]
  end

  defp deps do
    [
      {:fsm, "~> 0.3.0"},
      {:ranch, "~> 1.5", override: true},
      {:poolboy, "~> 1.5.1"},
      {:epqueue, github: "silviucpp/epqueue"},
      # documentation
      {:ex_doc, "~> 0.16", only: [:dev, :docs], runtime: false},
      # documentation coverage
      {:inch_ex, "~> 0.5", only: [:dev, :docs], runtime: false},
      # code linter
      {:credo, "~> 0.9.2", only: [:dev, :test], runtime: false},
      # code coverage
      {:excoveralls, "~> 0.7.4", only: [:dev, :test], runtime: false},
      # type safety
      {:dialyxir, "~> 0.5.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check_consistency: [
        "dialyzer",
        "credo --all --strict",
        "inch --depth 2",
        "test --cover"
      ]
    ]
  end
end
