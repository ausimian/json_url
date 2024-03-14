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

  test "empty string is encode as e" do
    assert "e" == JsonUrl.encode("")
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

  property "ascii strings round-trip" do
    check all(s <- string(:ascii)) do
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
    scalars = one_of([integer(), boolean(), string(:ascii), specials()])

    objects =
      tree(scalars, fn nested ->
        one_of([list_of(nested), map_of(string(:ascii, min_length: 1), nested, min_length: 1)])
      end)

    check all(o <- objects) do
      assert {:ok, ^o} = JsonUrl.encode(o) |> JsonUrl.decode()
    end
  end
end
