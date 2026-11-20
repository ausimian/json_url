defmodule JsonUrl do
  @moduledoc """
  Functions for encoding and decoding terms to [JsonUrl](https://github.com/jsonurl/specification) format.

  Both directions use the specification's address-bar query string friendly
  (AQF) syntax: characters that would otherwise be read as structure, as a
  number or as a keyword are escaped with `!`, a space is written as `+`, and
  anything that isn't safe in a URL query is percent-encoded.
  """

  defguardp is_hex(c) when c in ?0..?9 or c in ?A..?F or c in ?a..?f

  @doc """
  Encode a term to a JsonUrl 'address-bar friendly' string.

  The result contains only characters that are safe in a URL query string,
  so it can be used as a query parameter value without further encoding.
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
  Decode a JsonUrl string to an Elixir term.

  Pass the text exactly as `encode/1` produced it. If it went into the URL
  as-is, that is the raw query text, before any URL decoding: a framework's
  decoded parameters would already have turned `+` into a space and decoded
  `%` sequences once. If it was form-encoded on the way in (for example with
  `URI.encode_query/1`), pass the value after that form-decoding instead.

  Percent-encoded characters are decoded before they are read, so `%28`
  opens a composite and `%21` is the `!` escape. The exceptions are `%2B`,
  `%26` and `%3D`, which are always a literal `+`, `&` and `=`. Malformed
  percent-encoding, invalid UTF-8, and a raw space, `&`, `=` or control
  character are errors.

  ## Options

    * `:legacy` - when `true`, read `%`, `&`, `=` and control characters as
      json_url 0.2.0 and 0.3.0 did: `%` is an ordinary character, and a raw
      `&`, `=` or control character is accepted as part of a string. Use
      this for URLs produced by those versions. Defaults to `false`.
  """
  @spec decode(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def decode(s, opts \\ []) do
    with {:ok, text, rest} <- normalize(s, Keyword.get(opts, :legacy, false)),
         :ok <- check_utf8(text) do
      case __MODULE__.Parser.value(text) do
        {:ok, [parsed], "", _, _, _} when rest == "" ->
          {:ok, parsed}

        {:ok, _, _, _, _, _} ->
          {:error, :incomplete}

        {:error, error, _, _, _, _} ->
          {:error, error}
      end
    end
  end

  defp check_utf8(text) do
    if String.valid?(text), do: :ok, else: {:error, :invalid_utf8}
  end

  # Returns the text the parser should read, plus any input left over from
  # the first raw character that can't appear in JsonUrl text.
  defp normalize(text, true) do
    case :binary.split(text, " ") do
      [all] -> {:ok, all, ""}
      [head, tail] -> {:ok, head, " " <> tail}
    end
  end

  defp normalize(text, false), do: percent_decode(text, [], false)

  # Decodes percent-encoded characters so they read as if they were raw. A
  # decoded `+` is a literal plus, so it becomes the escape `!+` unless it is
  # already the value of a pending escape. Decoded spaces, controls, `&` and
  # `=` pass through as string content: the raw characters stop the scan
  # instead, so they never reach the parser.
  defp percent_decode(<<?%, a, b, rest::binary>>, acc, escaping?)
       when is_hex(a) and is_hex(b) do
    case String.to_integer(<<a, b>>, 16) do
      ?+ when escaping? -> percent_decode(rest, [acc, ?+], false)
      ?+ -> percent_decode(rest, [acc, "!+"], false)
      ?! -> percent_decode(rest, [acc, ?!], not escaping?)
      byte -> percent_decode(rest, [acc, byte], false)
    end
  end

  defp percent_decode(<<?%, _::binary>>, _acc, _escaping?),
    do: {:error, :invalid_percent_encoding}

  defp percent_decode(<<c, _::binary>> = rest, acc, _escaping?)
       when c in [?\s, ?&, ?=, 0x7F] or c < 0x20,
       do: {:ok, IO.iodata_to_binary(acc), rest}

  defp percent_decode(<<?!, rest::binary>>, acc, escaping?),
    do: percent_decode(rest, [acc, ?!], not escaping?)

  defp percent_decode(<<c, rest::binary>>, acc, _escaping?),
    do: percent_decode(rest, [acc, c], false)

  defp percent_decode(<<>>, acc, _escaping?), do: {:ok, IO.iodata_to_binary(acc), ""}

  defp escape(s), do: for(<<c <- s>>, into: "", do: escape_byte(c))

  defp escape_byte(?\s), do: "+"
  defp escape_byte(c) when c in [?(, ?), ?,, ?:, ?!, ?+], do: <<?!, c>>

  defp escape_byte(c) when c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in ~c"-._~$*/;?@'",
    do: <<c>>

  defp escape_byte(c), do: "%" <> Base.encode16(<<c>>)

  defmodule Parser do
    @moduledoc false
    import NimbleParsec

    @escaped [?+, ?!, ?(, ?), ?,, ?:]
    @unescaped for(c <- @escaped, do: {:not, c})

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
