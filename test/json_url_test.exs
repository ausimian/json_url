defmodule JsonUrlTest.Encoder030 do
  @moduledoc false
  # The json_url 0.3.0 encoder (unchanged since 0.2.0), verbatim, so the
  # legacy decoding option can be checked against the URLs those versions
  # actually produced.

  defguardp is_digit(c) when c >= ?0 and c <= ?9

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

  defp escape(s) do
    String.replace(s, ["+", "!", "(", ")", ",", ":", " "], fn
      " " -> "+"
      m -> "!" <> m
    end)
  end
end

defmodule JsonUrlTest do
  use ExUnit.Case
  use ExUnitProperties

  defp specials do
    one_of([constant(nil), constant("null"), constant("true"), constant("false")])
  end

  test "encode nil", do: assert("null" == JsonUrl.encode(nil))
  test "encode true", do: assert("true" == JsonUrl.encode(true))
  test "encode false", do: assert("false" == JsonUrl.encode(false))

  test "encode strings of reserved words" do
    assert "!null" == JsonUrl.encode("null")
    assert "!true" == JsonUrl.encode("true")
    assert "!false" == JsonUrl.encode("false")
  end

  test "empty string is encode as !e" do
    assert "!e" == JsonUrl.encode("")
  end

  test "numeric strings are escaped" do
    assert "!123" == JsonUrl.encode("123")
  end

  test "spaces are escaped" do
    assert "foo+bar" == JsonUrl.encode("foo bar")
  end

  test "plus sign is escaped" do
    assert "foo!+bar" == JsonUrl.encode("foo+bar")
  end

  test "propagate errors" do
    assert {:error, _} = JsonUrl.decode("")
  end

  test "handle incomplete parse" do
    assert {:error, :incomplete} = JsonUrl.decode("123 ")
  end

  describe "decoding numbers" do
    test "fractions and exponents decode as floats" do
      assert {:ok, 1.25} = JsonUrl.decode("1.25")
      assert {:ok, -0.125} = JsonUrl.decode("-0.125")
      assert {:ok, 100.0} = JsonUrl.decode("1e2")
      assert {:ok, 100.0} = JsonUrl.decode("1e+2")
      assert {:ok, -3.0e-4} = JsonUrl.decode("-3E-4")
    end

    test "floats decode inside composites" do
      assert {:ok, %{"x" => [1.5, -0.25, 100.0]}} = JsonUrl.decode("(x:(1.5,-0.25,1e+2))")
    end

    test "integers decode as integers" do
      assert {:ok, 42} = JsonUrl.decode("42")
      assert {:ok, -7} = JsonUrl.decode("-7")
      assert {:ok, 9_223_372_036_854_775_807} = JsonUrl.decode("9223372036854775807")
    end

    test "text outside the JSON number grammar decodes as a string" do
      for text <- ["001", "-01", "1.", "1e", "0x10", ".5", "-"] do
        assert {:ok, ^text} = JsonUrl.decode(text)
      end
    end

    test "a number prefix does not make the token a number" do
      assert {:ok, "16 Pro"} = JsonUrl.decode("16+Pro")
      assert {:ok, "-3 days"} = JsonUrl.decode("-3+days")
      assert {:ok, "123 "} = JsonUrl.decode("123+")
    end

    test "a float too large to represent is an error" do
      assert {:error, _} = JsonUrl.decode("1e400")
      assert {:error, _} = JsonUrl.decode("(1e400)")
    end
  end

  describe "decoding keywords" do
    test "a keyword prefix does not make the token a keyword" do
      assert {:ok, "trueish"} = JsonUrl.decode("trueish")
      assert {:ok, "false-positive"} = JsonUrl.decode("false-positive")
      assert {:ok, "nullary"} = JsonUrl.decode("nullary")
      assert {:ok, "false alarm"} = JsonUrl.decode("false+alarm")
    end
  end

  describe "decoding escaped literals" do
    test "an escape makes the literal a string" do
      assert {:ok, "true"} = JsonUrl.decode("!true")
      assert {:ok, "123"} = JsonUrl.decode("!123")
      assert {:ok, "1.5"} = JsonUrl.decode("!1.5")
      assert {:ok, "16 Pro"} = JsonUrl.decode("!16+Pro")
    end
  end

  describe "decoding composites" do
    test "object keys are always strings" do
      assert {:ok, %{"1" => 2}} = JsonUrl.decode("(1:2)")
      assert {:ok, %{"true" => 1}} = JsonUrl.decode("(true:1)")
      assert {:ok, %{"null" => nil}} = JsonUrl.decode("(null:null)")
      assert {:ok, %{"" => 1}} = JsonUrl.decode("(!e:1)")
    end

    test "objects must contain only key-value members" do
      assert {:error, _} = JsonUrl.decode("(a:1,b)")
      assert {:error, _} = JsonUrl.decode("(a:1,(b:2))")
      assert {:error, _} = JsonUrl.decode("(a:1,())")
    end

    test "arrays must contain only values" do
      assert {:error, _} = JsonUrl.decode("(a,b:1)")
      assert {:error, _} = JsonUrl.decode("(1,(2),c:3)")
    end

    test "nested composites of either kind are valid members" do
      assert {:ok, []} = JsonUrl.decode("()")
      assert {:ok, %{"a" => []}} = JsonUrl.decode("(a:())")
      assert {:ok, [%{"a" => 1}, "b"]} = JsonUrl.decode("((a:1),b)")
      assert {:ok, ["a", %{"b" => 1}]} = JsonUrl.decode("(a,(b:1))")
    end
  end

  describe "encoding strings" do
    test "only strings that would read back as numbers are escaped" do
      assert "16+Pro" == JsonUrl.encode("16 Pro")
      assert "001" == JsonUrl.encode("001")
      assert "false-positive" == JsonUrl.encode("false-positive")
      assert "!1.5" == JsonUrl.encode("1.5")
      assert "!-0" == JsonUrl.encode("-0")
    end

    test "escaping is decided on the encoded form" do
      # "1e 2" encodes its space as `+`, which would read back as a number.
      assert "!1e+2" == JsonUrl.encode("1e 2")
      assert "1e!+2" == JsonUrl.encode("1e+2")
    end

    test "number-like strings round-trip" do
      for s <- ["1e 2", "1.5", "-0", "1e+2", "001", "-1", "16 Pro", "1e400", "true", "-"] do
        assert {:ok, ^s} = JsonUrl.encode(s) |> JsonUrl.decode()
      end
    end
  end

  describe "decoding percent-encoded text" do
    test "percent-encoded characters decode to string content" do
      assert {:ok, "A B"} = JsonUrl.decode("A%20B")
      assert {:ok, "é"} = JsonUrl.decode("%C3%A9")
      assert {:ok, "裝置"} = JsonUrl.decode("%E8%A3%9D%E7%BD%AE")
      assert {:ok, "🧪"} = JsonUrl.decode("%F0%9F%A7%AA")
      assert {:ok, "é"} = JsonUrl.decode("%c3%a9")
    end

    test "percent-encoded text is decoded only once" do
      assert {:ok, "%2B"} = JsonUrl.decode("%252B")
      assert {:ok, "%20"} = JsonUrl.decode("%2520")
    end

    test "an encoded plus, ampersand or equals sign is literal" do
      assert {:ok, "A+B"} = JsonUrl.decode("A%2BB")
      assert {:ok, "A&B=C"} = JsonUrl.decode("A%26B%3DC")
      assert {:ok, "1e+2"} = JsonUrl.decode("1e%2B2")
    end

    test "an encoded escape or escape value behaves like the raw one" do
      assert {:ok, ""} = JsonUrl.decode("%21e")
      assert {:ok, "!"} = JsonUrl.decode("%21%21")
      assert {:ok, "(a)"} = JsonUrl.decode("%21%28a%21%29")

      for text <- ["A!%2BB", "A%21+B", "A%21%2BB"] do
        assert {:ok, "A+B"} = JsonUrl.decode(text)
      end
    end

    test "encoded structural characters and literals are read as if raw" do
      assert {:ok, ["a", "b"]} = JsonUrl.decode("%28a%2Cb%29")
      assert {:ok, %{"a" => 1}} = JsonUrl.decode("(a%3A1)")
      assert {:ok, 1} = JsonUrl.decode("%31")
      assert {:ok, true} = JsonUrl.decode("%74rue")
    end

    test "encoded whitespace and controls are string content" do
      assert {:ok, "a\tb"} = JsonUrl.decode("a%09b")
      assert {:ok, "a\nb"} = JsonUrl.decode("a%0Ab")
      assert {:ok, <<?a, 0, ?b>>} = JsonUrl.decode("a%00b")
      assert {:ok, "1e 2"} = JsonUrl.decode("1e%202")
    end

    test "malformed percent-encoding is an error" do
      for text <- ["%", "%2", "%GG", "a%", "!75%"] do
        assert {:error, _} = JsonUrl.decode(text)
      end
    end

    test "percent-encoding that isn't UTF-8 is an error" do
      assert {:error, _} = JsonUrl.decode("%C3%28")
      assert {:error, _} = JsonUrl.decode("%FF")
    end

    test "raw characters that must be encoded are errors" do
      for text <- ["a b", "a\tb", "a\nb", <<?a, 0, ?b>>, "a&b", "a=b"] do
        assert {:error, _} = JsonUrl.decode(text)
      end
    end
  end

  describe "decoding with legacy: true" do
    test "percent signs are ordinary characters" do
      assert {:ok, "A%20B"} = JsonUrl.decode("A%20B", legacy: true)
      assert {:ok, "75%"} = JsonUrl.decode("!75%", legacy: true)
      assert {:ok, "%41"} = JsonUrl.decode("%41", legacy: true)
    end

    test "raw ampersands, equals signs and controls are accepted" do
      assert {:ok, "A&B=C"} = JsonUrl.decode("A&B=C", legacy: true)
      assert {:ok, "a\tb"} = JsonUrl.decode("a\tb", legacy: true)
    end

    test "a raw space is still an error" do
      assert {:error, :incomplete} = JsonUrl.decode("123 ", legacy: true)
      assert {:error, _} = JsonUrl.decode("a b", legacy: true)
    end
  end

  describe "encoding for URLs" do
    test "characters that aren't safe in a query are percent-encoded" do
      assert "A%26B%3DC" == JsonUrl.encode("A&B=C")
      assert "A%23B" == JsonUrl.encode("A#B")
      assert "75%25" == JsonUrl.encode("75%")
      assert "%C3%A9" == JsonUrl.encode("é")
      assert "a%09b%0Ac%00" == JsonUrl.encode("a\tb\nc\0")
    end

    test "structural characters are escaped, not percent-encoded" do
      assert "!(a!,b!:c!)" == JsonUrl.encode("(a,b:c)")
    end
  end

  property "encoded strings contain only query-safe characters" do
    check all(s <- one_of([string(:utf8), string(:ascii)])) do
      encoded = JsonUrl.encode(s)
      assert encoded =~ ~r/\A(?:[A-Za-z0-9\-._~$*\/;?@'!()+,:]|%[0-9A-F]{2})*\z/
      assert {:ok, ^s} = JsonUrl.decode(encoded)
    end
  end

  property "decoding never raises" do
    alphabet = [?%, ?!, ?(, ?), ?,, ?:, ?+, ?e, ?t, ?\s, ?&, ?=, ?\t, ?0..?9, ?A..?F]

    check all(
            text <- one_of([string(alphabet), binary()]),
            legacy <- boolean()
          ) do
      assert match?({:ok, _}, JsonUrl.decode(text, legacy: legacy)) or
               match?({:error, _}, JsonUrl.decode(text, legacy: legacy))
    end
  end

  property "legacy decoding reads what json_url 0.3.0 encoded" do
    number_like = string([?0..?9, ?-, ?+, ?., ?e, ?E, ?\s, ?%])

    scalars =
      one_of([integer(), boolean(), string(:utf8), string(:ascii), number_like, specials()])

    values =
      tree(scalars, fn nested ->
        one_of([list_of(nested), map_of(string(:utf8, min_length: 1), nested, min_length: 1)])
      end)

    check all(value <- values) do
      encoded = JsonUrlTest.Encoder030.encode(value)
      assert {:ok, ^value} = JsonUrl.decode(encoded, legacy: true)
    end
  end

  property "atoms round-trip" do
    check all(a <- one_of([atom(:alphanumeric), atom(:alias)])) do
      {:ok, ao} = JsonUrl.encode(a) |> JsonUrl.decode()
      assert ^a = String.to_existing_atom(ao)
    end
  end

  property "specials round-trip" do
    check all(s <- specials()) do
      assert {:ok, ^s} = JsonUrl.encode(s) |> JsonUrl.decode()
    end
  end

  property "booleans round-trip" do
    check all(b <- boolean()) do
      assert {:ok, ^b} = JsonUrl.encode(b) |> JsonUrl.decode()
    end
  end

  property "integers round-trip" do
    check all(i <- integer()) do
      assert {:ok, ^i} = JsonUrl.encode(i) |> JsonUrl.decode()
    end
  end

  property "floats round-trip" do
    check all(f <- float()) do
      assert {:ok, ^f} = JsonUrl.encode(f) |> JsonUrl.decode()
    end
  end

  property "number-like strings round-trip" do
    check all(s <- string([?0..?9, ?-, ?+, ?., ?e, ?E, ?\s], min_length: 1)) do
      assert {:ok, ^s} = JsonUrl.encode(s) |> JsonUrl.decode()
    end
  end

  property "ascii strings round-trip" do
    check all(s <- string(:ascii)) do
      assert {:ok, ^s} = JsonUrl.encode(s) |> JsonUrl.decode()
    end
  end

  property "utf-8 strings round-trip" do
    check all(s <- string(:utf8)) do
      assert {:ok, ^s} = JsonUrl.encode(s) |> JsonUrl.decode()
    end
  end

  property "lists round trip" do
    check all(l <- list_of(one_of([integer(), boolean(), string(:ascii)]))) do
      assert {:ok, ^l} = JsonUrl.encode(l) |> JsonUrl.decode()
    end
  end

  property "maps round trip" do
    check all(m <- map_of(string(:ascii), one_of([integer(), boolean(), string(:ascii)]))) do
      {:ok, mo} = JsonUrl.encode(m) |> JsonUrl.decode()
      assert ^m = Map.new(mo)
    end
  end

  property "nested structures round trip" do
    scalars = one_of([integer(), float(), boolean(), string(:ascii), specials()])

    objects =
      tree(scalars, fn nested ->
        one_of([list_of(nested), map_of(string(:ascii, min_length: 1), nested, min_length: 1)])
      end)

    check all(o <- objects) do
      assert {:ok, ^o} = JsonUrl.encode(o) |> JsonUrl.decode()
    end
  end
end
