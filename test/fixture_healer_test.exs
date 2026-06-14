defmodule Credence.FixtureHealerTest do
  use ExUnit.Case, async: true

  alias Credence.FixtureHealer, as: H
  alias Credence.MetaTestSupport, as: Meta

  defp ok?(fixture_src) do
    "code = #{fixture_src}"
    |> Sourceror.parse_string!()
    |> Meta.fixtures()
    |> List.first()
    |> Meta.fixture_ok?()
  end

  defp value_of(node),
    do: elem(Code.eval_string(Sourceror.to_string(node), [], file: "nofile"), 0)

  defp values(src),
    do: src |> Sourceror.parse_string!() |> Meta.fixtures() |> Enum.map(&value_of/1)

  describe "fixture_ok?/1 — the convention, both directions" do
    test "clean single-line plain is allowed" do
      assert ok?(~S|"Enum.filter(l, fn x -> x end)"|)
    end

    test "plain with a newline is flagged" do
      refute ok?("\"a\\nb\"")
    end

    test "plain with a quote is flagged" do
      refute ok?(~S|"a \"b\" c"|)
    end

    test "~S'…' single-line sigil is allowed" do
      assert ok?(~S|~S'a "b" c'|)
    end

    test "~S'…' carrying a newline is flagged" do
      refute ok?("~S'a\\nb'")
    end

    test "a heredoc is allowed" do
      assert ok?("\"\"\"\nfoo\n\"\"\"")
    end
  end

  describe "heal_source/1 — the 3 conversions" do
    test "newline value → heredoc" do
      assert H.heal_source("code = \"a\\nb\"\n") == {"code = \"\"\"\na\nb\n\"\"\"\n", 0}
    end

    test "quoted single-line value → ~S'…'" do
      assert H.heal_source(~S|code = "a \"b\" c"| <> "\n") == {~S|code = ~S'a "b" c'| <> "\n", 0}
    end

    test "newline AND quote → heredoc with raw quotes" do
      assert H.heal_source("code = \"x\\ny \\\"q\\\"\"\n") ==
               {"code = \"\"\"\nx\ny \"q\"\n\"\"\"\n", 0}
    end

    test "clean single-line plain is left untouched (no-op)" do
      src = "code = \"plain ok\"\n"
      assert H.heal_source(src) == {src, 0}
    end

    test "an existing heredoc is left untouched" do
      src = "code = \"\"\"\nfoo\nbar\n\"\"\"\n"
      assert H.heal_source(src) == {src, 0}
    end

    test "is idempotent" do
      {once, _} = H.heal_source("code = \"a\\nb\"\n")
      assert H.heal_source(once) == {once, 0}
    end

    test "heals every flagged fixture in a file and preserves each value (±trailing nl)" do
      src = "input = \"a\\nb\"\nexpected = \"a \\\"q\\\"\"\nclean = \"plain\"\n"
      {healed, residue} = H.heal_source(src)

      assert residue == 0
      assert match?({:ok, _}, Code.string_to_quoted(healed))

      assert healed
             |> Sourceror.parse_string!()
             |> Meta.fixtures()
             |> Enum.all?(&Meta.fixture_ok?/1)

      for {v0, v1} <- Enum.zip(values(src), values(healed)) do
        assert v1 == v0 or v1 == v0 <> "\n"
      end
    end
  end

  describe "heal_file/1" do
    test "rewrites a flagged fixture in place" do
      path = Path.join(System.tmp_dir!(), "healer_#{System.unique_integer([:positive])}.exs")
      File.write!(path, "code = \"a\\nb\"\n")
      on_exit(fn -> File.rm(path) end)

      H.heal_file(path)
      healed = File.read!(path)

      assert healed == "code = \"\"\"\na\nb\n\"\"\"\n"
      assert ok_node?(healed)
    end

    test "leaves a clean file untouched" do
      path = Path.join(System.tmp_dir!(), "healer_#{System.unique_integer([:positive])}.exs")
      src = "code = \"already clean\"\n"
      File.write!(path, src)
      on_exit(fn -> File.rm(path) end)

      H.heal_file(path)
      assert File.read!(path) == src
    end

    test "skips @allow files" do
      [{allow_path, _} | _] = Map.to_list(Meta.allow())
      before = File.read!(allow_path)
      H.heal_file(allow_path)
      assert File.read!(allow_path) == before
    end
  end

  defp ok_node?(src) do
    src |> Sourceror.parse_string!() |> Meta.fixtures() |> List.first() |> Meta.fixture_ok?()
  end
end
