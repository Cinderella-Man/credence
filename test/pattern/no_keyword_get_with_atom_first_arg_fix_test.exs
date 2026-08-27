defmodule Credence.Pattern.NoKeywordGetWithAtomFirstArgFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoKeywordGetWithAtomFirstArg

  # ── 2-arg: extracts default ───────────────────────────────────

  describe "2-arg: extracts default" do
    test "fn default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:clock, fn -> :default end)"),
        "fn -> :default end"
      )
    end

    test "integer default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:timeout, 5000)"),
        "5000"
      )
    end

    test "atom default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:key, :fallback)"),
        ":fallback"
      )
    end

    test "variable default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:key, my_default)"),
        "my_default"
      )
    end
  end

  # ── 3-arg: extracts default ───────────────────────────────────

  describe "3-arg: extracts default" do
    test "atom key and default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:key, :lookup, :fallback)"),
        """
        (:lookup
        :fallback)
        """
      )
    end

    test "fn default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:clock, :key, fn -> :default end)"),
        """
        (:key
        fn -> :default end)
        """
      )
    end

    test "call in the key slot is evaluated before the default is returned" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:key, compute_key(), default)"),
        """
        (compute_key()
        default)
        """
      )
    end

    test "effectful key in the emitted repair still raises" do
      source = ~S'Keyword.get(:key, raise("boom"), :fallback)'
      emitted = fix(NoKeywordGetWithAtomFirstArg, source)

      confirm_fix(emitted, """
      (raise "boom"
      :fallback)
      """)

      original_fixture =
        "defmodule NoKeywordGetAtomFirstArgOriginalEffectFixture do\n" <>
          "  @result #{source}\nend"

      emitted_fixture =
        "defmodule NoKeywordGetAtomFirstArgEmittedEffectFixture do\n" <>
          "  @result #{emitted}\nend"

      expected_error =
        {:error, [%{message: "boom", position: 0, file: "credence_check.ex", severity: :error}]}

      assert Credence.RuleHelpers.compile_and_capture(original_fixture) == expected_error
      assert Credence.RuleHelpers.compile_and_capture(emitted_fixture) == expected_error
    end
  end

  # ── piped calls ───────────────────────────────────────────────

  describe "piped calls" do
    test "piped atom 2-arg" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, ":atom |> Keyword.get(:key)"),
        ":key"
      )
    end

    test "piped atom 3-arg" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, ":atom |> Keyword.get(:key, :default)"),
        """
        (:key
        :default)
        """
      )
    end

    test "piped atom followed by another pipe stage" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, ":atom |> Keyword.get(:key) |> foo()"),
        ":key |> foo()"
      )
    end

    test "bad call as pipe LHS" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:a, :b) |> foo()"),
        ":b |> foo()"
      )
    end
  end

  # ── realistic context ─────────────────────────────────────────

  describe "realistic context" do
    test "preserves surrounding code in module" do
      code = """
      defmodule Example do
        def init(:ok) do
          clock = Keyword.get(:clock, fn -> :default end)
          %{clock: clock}
        end
      end
      """

      expected = """
      defmodule Example do
        def init(:ok) do
          clock = fn -> :default end
          %{clock: clock}
        end
      end
      """

      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), expected)
    end

    test "in assignment" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "clock = Keyword.get(:clock, fn -> :default end)"),
        "clock = fn -> :default end"
      )
    end

    test "as function argument" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "do_something(Keyword.get(:key, :val))"),
        "do_something(:val)"
      )
    end

    test "nested violations collapse to the innermost default" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "Keyword.get(:a, Keyword.get(:b, :c))"),
        ":c"
      )
    end

    test "good piped call on the same line is untouched" do
      confirm_fix(
        fix(NoKeywordGetWithAtomFirstArg, "foo |> Keyword.get(:a); Keyword.get(:atom, :b)"),
        "foo |> Keyword.get(:a); :b"
      )
    end
  end

  # ── no-ops ────────────────────────────────────────────────────

  describe "no-ops" do
    test "variable first arg unchanged" do
      code = "Keyword.get(opts, :name)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "variable first arg with default unchanged" do
      code = ~S'Keyword.get(opts, :name, "default")'
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "piped variable unchanged" do
      code = "opts |> Keyword.get(:name)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "Map.get with atom first arg unchanged" do
      code = "Map.get(:atom, :key)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "no Keyword.get at all unchanged" do
      code = "List.last(acc)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "4-arg call unchanged (no /4, no default slot)" do
      code = "Keyword.get(:a, :b, :c, :d)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "piped 3-arg call unchanged (no /4)" do
      code = ":a |> Keyword.get(:b, :c, :d)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end

    test "module alias first arg unchanged" do
      code = "Keyword.get(Foo, :key)"
      confirm_fix(fix(NoKeywordGetWithAtomFirstArg, code), code)
    end
  end

  # ── round-trip ────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule E do
        def a, do: Keyword.get(:key1, :val1)
        def b, do: Keyword.get(:key2, :val2)
      end
      """

      assert check(NoKeywordGetWithAtomFirstArg, fix(NoKeywordGetWithAtomFirstArg, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule E do
        def a, do: Keyword.get(:key1, :val1)
        def b, do: Keyword.get(:key2, :val2)
      end
      """

      assert valid_syntax?(fix(NoKeywordGetWithAtomFirstArg, code))
    end
  end
end
