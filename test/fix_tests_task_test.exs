defmodule Credence.FixTestsTaskTest do
  # async: false — fix_file/1 runs the rule (compiles/loads modules).
  use ExUnit.Case, async: false

  alias Mix.Tasks.Credence.FixTests

  # A fix test whose `expected` is WRONG (the LLM guessed). UseMapJoin rewrites
  # `Enum.map(..) |> Enum.join(sep)` → `Enum.map_join(.., sep, ..)`.
  @wrong_expected ~S'''
  defmodule Credence.Pattern.UseMapJoinFixTest do
    use Credence.RuleCase, async: true

    test "rewrites map then join" do
      input = """
      defmodule Example do
        def f(xs) do
          Enum.map(xs, &Integer.to_string/1) |> Enum.join(", ")
        end
      end
      """

      expected = """
      WRONG PLACEHOLDER
      """

      assert fix(UseMapJoin, input) == expected
    end
  end
  '''

  defp in_temp(content, fun) do
    dir = Path.join(System.tmp_dir!(), "fixtests_#{System.unique_integer([:positive])}/test/pattern")
    File.mkdir_p!(dir)
    path = Path.join(dir, "use_map_join_fix_test.exs")
    File.write!(path, content)
    try do
      fun.(path)
    after
      File.rm_rf!(Path.dirname(Path.dirname(Path.dirname(path))))
    end
  end

  test "canonicalizes a wrong `expected` to the rule's real output" do
    in_temp(@wrong_expected, fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      refute out =~ "WRONG PLACEHOLDER"
      assert out =~ "Enum.map_join(xs, \", \", &Integer.to_string/1)"
      # still well-formed + still a whole-string == assertion (FixMetaTest-clean)
      assert match?({:ok, _}, Sourceror.parse_string(out))
      assert out =~ "assert fix(UseMapJoin, input) == expected"
    end)
  end

  # The `=~` shape: `result = fix(...)` then a run of `assert/refute result =~ …`.
  @tilde_shape ~S'''
  defmodule Credence.Pattern.UseMapJoinFixTest do
    use Credence.RuleCase, async: true

    test "rewrites map then join" do
      input = """
      defmodule Example do
        def f(xs) do
          Enum.map(xs, &Integer.to_string/1) |> Enum.join(", ")
        end
      end
      """

      result = fix(UseMapJoin, input)

      assert result =~ "Enum.map_join"
      refute result =~ "Enum.join"
      assert valid_syntax?(result)
    end
  end
  '''

  test "collapses a `result =~ …` run into one inline `fix(...) == \"\"\"…\"\"\"`" do
    in_temp(@tilde_shape, fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      refute out =~ "result =~"
      assert out =~ "assert fix(UseMapJoin, input) == "
      assert out =~ "Enum.map_join(xs, \", \", &Integer.to_string/1)"
      assert match?({:ok, _}, Sourceror.parse_string(out))
    end)
  end

  test "is idempotent — a correct fix test is left unchanged" do
    in_temp(@wrong_expected, fn path ->
      FixTests.fix_file(path)
      once = File.read!(path)
      FixTests.fix_file(path)
      assert File.read!(path) == once
    end)
  end
end
