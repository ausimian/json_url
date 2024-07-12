defmodule JsonUrl do
  @moduledoc """
  Functions for encoding and decoding terms to [JsonUrl](https://github.com/jsonurl/specification) format.
  """
  defguardp is_digit(c) when c >= ?0 and c <= ?9

  @doc """
  Encode a term to a JsonUrl 'address-bar friendly' string.
  """
  @spec encode(nil | boolean() | atom() | integer() | binary() | map() | list()) :: String.t()
  def encode(nil), do: "null"
  def encode(f) when is_boolean(f), do: to_string(f)
  def encode(s) when is_atom(s), do: encode(Atom.to_string(s))
  def encode(n) when is_integer(n) or is_float(n), do: to_string(n)

  def encode(<<>>), do: "!e"
  def encode(s) when s in ["true", "false", "null"], do: <<?!, s::binary>>

  def encode(<<?-, c, rest::binary>>) when is_digit(c) do
    <<?!, ?-, c, escape(rest)::binary>>
  end

  def encode(<<c, rest::binary>>) when is_digit(c) do
    <<?!, c, escape(rest)::binary>>
  end

  def encode(s) when is_binary(s), do: escape(s)

  def encode(m) when is_map(m) do
    props = for {k, v} <- m, do: [encode(k), ?:, encode(v)]
    IO.iodata_to_binary([?(, Enum.join(props, ","), ?)])
  end

  def encode(l) when is_list(l) do
    props = for v <- l, do: encode(v)
    IO.iodata_to_binary([?(, Enum.join(props, ","), ?)])
  end

  @doc """
  Decode a JsonUrl string to an Elixir term
  """
  @spec decode(String.t()) :: {:ok, any()} | {:error, any()}
  def decode(s) do
    case __MODULE__.Parser.expr(s) do
      {:ok, [parsed], "", _, _, _} ->
        {:ok, parsed}

      {:ok, _, _, _, _, _} ->
        {:error, :incomplete}

      {:error, error, _, _, _, _} ->
        {:error, error}
    end
  end

  defp escape(s) do
    String.replace(s, ["+", "!", "(", ")", ",", ":", " "], fn
      " " -> "+"
      m -> "!" <> m
    end)
  end

  defmodule Parser do
    @moduledoc false
    import NimbleParsec

    @escaped [?+, ?!, ?(, ?), ?,, ?:]
    @unescaped [{:not, ?\s} | for(c <- @escaped, do: {:not, c})]

    null = string("null") |> replace(nil)
    tval = string("true") |> replace(true)
    fval = string("false") |> replace(false)

    minus = string("-") |> replace(-1)

    int =
      optional(minus)
      |> integer(min: 1)
      |> reduce({Enum, :product, []})

    empty_string = string("!e") |> replace("")

    tok =
      choice([
        string("!") |> ascii_string(@escaped, 1) |> reduce(:unescape),
        string("!") |> ascii_string([?-, ?0..?9], min: 1) |> reduce(:unescape),
        string("!") |> ascii_string([?t, ?f, ?n], 1) |> reduce(:unescape),
        string("+") |> replace(" "),
        utf8_string(@unescaped, min: 1)
      ])

    str =
      choice([
        empty_string,
        times(tok, min: 1) |> reduce({Enum, :join, []})
      ])

    atom = choice([null, tval, fval, int, str])
    empty = string("()") |> replace([])
    object = ignore(string("(")) |> parsec(:exprs) |> ignore(string(")")) |> reduce(:to_object)

    defparsec(
      :pair,
      choice([
        str |> ignore(string(":")) |> parsec(:expr) |> reduce({List, :to_tuple, []}),
        parsec(:expr)
      ])
    )

    defparsec(:expr, choice([atom, empty, object]))

    defparsec(
      :exprs,
      choice([
        parsec(:pair) |> ignore(string(",")) |> parsec(:exprs),
        parsec(:pair)
      ])
    )

    defp unescape(["!", ch]), do: ch

    defp to_object([{_, _} | _] = p), do: Map.new(p)
    defp to_object(p), do: p
  end
end
