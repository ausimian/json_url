defmodule JsonUrl.MixProject do
  use Mix.Project

  @vsn "0.3.0"

  def project do
    [
      app: :json_url,
      description: "JsonUrl encoding and decoding support",
      version: @vsn,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/ausimian/json_url",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.4.0", runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:stream_data, "~> 1.1.1", only: :test}
    ]
  end

  defp package do
    [
      description: "JsonUrl encoding and decoding support",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/ausimian/json_url"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: @vsn,
      source_url: "https://github.com/ausimian/json_url",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ]
    ]
  end
end
