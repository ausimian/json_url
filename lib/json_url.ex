defmodule JsonUrl do
  @moduledoc """
  Functions for encoding and decoding terms to [JsonUrl](https://github.com/jsonurl/specification) format.
  """

  @doc """
  Encode a term to a JsonUrl 'address-bar friendly' string.
  """
  @spec encode(nil | boolean() | atom() | number() | binary() | map() | list()) :: String.t()
  def encode(nil), do: "null"
  def encode(f) when is_boolean(f), do: to_string(f)
  def encode(s) when is_atom(s), do: encode(Atom.to_string(s))
  def encode(n) when is_integer(n) or is_float(n), do: to_string(n)

  def encode(<<>>), do: "!e"

  def encode(s) when is_binary(s) do
    escaped = escape(s)

    # A string that would otherwise read back as a number or keyword is
    # prefixed with `!`, which escapes its first character.
    if __MODULE__.Parser.typed_literal?(escaped), do: "!" <> escaped, else: escaped
  end

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
    case __MODULE__.Parser.value(s) do
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

    # A literal is a run of these parts, ending at a structural character or
    # at the end of input. Parts are tagged so that the literal can be
    # classified as a whole once it has been read.
    part =
      choice([
        ignore(string("!")) |> ascii_string(@escaped, 1) |> unwrap_and_tag(:escaped),
        ignore(string("!")) |> ascii_string([?-, ?0..?9], min: 1) |> unwrap_and_tag(:escaped),
        ignore(string("!")) |> ascii_string([?t, ?f, ?n], 1) |> unwrap_and_tag(:escaped),
        string("+") |> unwrap_and_tag(:plus),
        utf8_string(@unescaped, min: 1) |> unwrap_and_tag(:raw)
      ])

    parts = times(part, min: 1)

    empty_string =
      string("!e")
      |> lookahead(choice([ascii_char([?), ?,, ?:]), eos()]))
      |> replace("")

    literal = parts |> post_traverse(:literal)

    # Object keys are always strings, even when they look like numbers.
    key = choice([empty_string, parts |> reduce(:to_text)])

    pair =
      key
      |> ignore(string(":"))
      |> parsec(:value)
      |> reduce({List, :to_tuple, []})

    comma = ignore(string(","))
    close = ignore(string(")"))

    # The first member decides whether a composite is an object or an array,
    # and every later member must be of the same kind.
    composite =
      ignore(string("("))
      |> choice([
        string(")") |> replace([]),
        pair |> repeat(comma |> concat(pair)) |> concat(close) |> reduce({Map, :new, []}),
        parsec(:value) |> repeat(comma |> parsec(:value)) |> concat(close) |> wrap()
      ])

    defparsec(:value, choice([composite, empty_string, literal]) |> label("a JsonUrl value"))

    @doc false
    @spec typed_literal?(String.t()) :: boolean()
    def typed_literal?(text), do: text in ["null", "true", "false"] or number?(text)

    defp number?(text),
      do: Regex.match?(~r/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/, text)

    defp literal(rest, parts, context, _line, _offset) do
      parts = Enum.reverse(parts)

      case classify(parts) do
        {:ok, value} -> {rest, [value], context}
        {:error, reason} -> {:error, reason}
      end
    end

    # Only a literal without escapes can be a keyword or number, and it is
    # matched as a whole before `+` is read as a space, so `1e+2` is a
    # number while `16+Pro` is the string "16 Pro".
    defp classify(parts) do
      if Enum.all?(parts, fn {tag, _} -> tag in [:raw, :plus] end) do
        parts |> Enum.map_join(fn {_, text} -> text end) |> typed(parts)
      else
        {:ok, to_text(parts)}
      end
    end

    defp typed("null", _), do: {:ok, nil}
    defp typed("true", _), do: {:ok, true}
    defp typed("false", _), do: {:ok, false}

    defp typed(raw, parts) do
      cond do
        not number?(raw) -> {:ok, to_text(parts)}
        String.contains?(raw, [".", "e", "E"]) -> to_float(raw)
        true -> {:ok, String.to_integer(raw)}
      end
    end

    defp to_float(raw) do
      case Float.parse(raw) do
        {float, ""} -> {:ok, float}
        _ -> {:error, "number out of range: #{raw}"}
      end
    end

    defp to_text(parts) do
      Enum.map_join(parts, fn
        {:plus, _} -> " "
        {_, text} -> text
      end)
    end
  end
end
