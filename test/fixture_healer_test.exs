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

  defp value_of(node) do
    {evaled, _diagnostics} =
      Code.with_diagnostics(fn ->
        Code.eval_string(Sourceror.to_string(node), [], file: "nofile")
      end)

    elem(evaled, 0)
  end

  defp values(src),
    do: src |> Sourceror.parse_string!() |> Meta.fixtures() |> Enum.map(&value_of/1)

  # Triple-quote delimiter as a 3-quote sigil, so no string literal in this file
  # (which is all about heredoc source) carries "more than 3 quotes".
  @tq ~s(""")
  defp heredoc(body), do: @tq <> "\n" <> body <> @tq
  defp assign(body), do: "code = " <> heredoc(body) <> "\n"

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

    test "a multi-content-line heredoc is allowed" do
      assert ok?(heredoc("foo\nbar\n"))
    end

    test "a single-content-line heredoc is flagged" do
      refute ok?(heredoc("foo\n"))
    end
  end

  describe "heal_source/1 — fixture form conversions" do
    test "newline value → heredoc" do
      assert H.heal_source("code = \"a\\nb\"\n") == {"code = \"\"\"\na\nb\n\"\"\"\n", 0}
    end

    test "quoted single-line value → ~S'…'" do
      assert H.heal_source(~S|code = "a \"b\" c"| <> "\n") == {~S|code = ~S'a "b" c'| <> "\n", 0}
    end

    test "newline AND quote → heredoc with raw quotes" do
      assert H.heal_source(~S|code = "x\ny \"q\""| <> "\n") == {assign("x\ny \"q\"\n"), 0}
    end

    test "clean single-line plain is left untouched (no-op)" do
      src = "code = \"plain ok\"\n"
      assert H.heal_source(src) == {src, 0}
    end

    test "a multi-content-line heredoc is left untouched" do
      src = assign("foo\nbar\n")
      assert H.heal_source(src) == {src, 0}
    end

    test "a single-content-line heredoc → plain" do
      assert H.heal_source(assign("foo\n")) == {"code = \"foo\"\n", 0}
    end

    test "a heredoc with a trailing blank line → plain (trailing newlines dropped)" do
      assert H.heal_source(assign("foo\n\n")) == {"code = \"foo\"\n", 0}
    end

    test "a single-content-line heredoc with a quote → ~S'…'" do
      assert H.heal_source(assign(~S|a "b" c| <> "\n")) == {~S|code = ~S'a "b" c'| <> "\n", 0}
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

  describe "heal_source/1 — fix comparison → confirm_fix" do
    defp heal(src), do: src |> H.heal_source() |> elem(0)

    test "assert fix(...) == expected becomes confirm_fix(...)" do
      src = """
      defmodule M do
        use Credence.RuleCase

        test "t" do
          assert fix(R, "a") == "b"
        end
      end
      """

      assert heal(src) =~ ~s|confirm_fix(fix(R, "a"), "b")|
      refute heal(src) =~ "=="
    end

    test "a qualified Mod.fix(...) == expected becomes confirm_fix(...)" do
      src = """
      defmodule M do
        use Credence.RuleCase

        test "t" do
          assert R.fix(source, diag) == "b"
        end
      end
      """

      assert heal(src) =~ ~s|confirm_fix(R.fix(source, diag), "b")|
    end

    test "a var bound to fix is recognised (result = fix(...); assert result == expected)" do
      src = """
      defmodule M do
        use Credence.RuleCase

        test "t" do
          result = fix(R, "a")
          assert result == "b"
        end
      end
      """

      assert heal(src) =~ ~s|confirm_fix(result, "b")|
    end

    test "merges confirm_fix into an existing scoped RuleCase import" do
      src = """
      defmodule M do
        use ExUnit.Case

        import Credence.RuleCase, only: [valid_syntax?: 1]

        test "t" do
          assert R.fix(source, diag) == "b"
        end
      end
      """

      healed = heal(src)
      assert healed =~ "import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]"
      # exactly one RuleCase import line (no shadowing second import)
      assert healed |> String.split("import Credence.RuleCase") |> length() == 2
    end

    test "leaves a non-fix == assertion alone" do
      src = """
      defmodule M do
        use Credence.RuleCase

        test "t" do
          assert analyze("a") == []
        end
      end
      """

      assert heal(src) == src
    end

    test "is idempotent (already confirm_fix)" do
      src = """
      defmodule M do
        use Credence.RuleCase

        test "t" do
          confirm_fix(fix(R, "a"), "b")
        end
      end
      """

      assert heal(src) == src
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
  end

  defp ok_node?(src) do
    src |> Sourceror.parse_string!() |> Meta.fixtures() |> List.first() |> Meta.fixture_ok?()
  end
end
