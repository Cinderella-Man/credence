defmodule Credence.Semantic.FixStructTestInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase,
    only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixStructTestInGuard
  alias Credence.RuleHelpers

  @real_message "cannot invoke remote function Map.get/2 inside a guard"

  defp fix(source, message \\ @real_message) do
    FixStructTestInGuard.fix(source, %{severity: :error, message: message, position: {2, 1}})
  end

  defp compile_and_send(source, expressions) do
    recipient = self() |> inspect() |> String.trim_leading("#PID")

    probe = """
    send(:erlang.list_to_pid(~c\"#{recipient}\"), {:dispatch_results, [#{Enum.join(expressions, ", ")}]})
    """

    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(source <> "\n" <> probe)
    assert_receive {:dispatch_results, results}
    results
  end

  describe "moves the struct test into the pattern" do
    test "the field sample" do
      input = """
      defmodule StructGuard do
        def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
        def f(v), do: {:plain, v}
      end
      """

      expected = """
      defmodule StructGuard do
        def f(%Regex{} = v), do: {:regex, v}
        def f(v), do: {:plain, v}
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "the operands the other way round" do
      input = """
      defmodule StructGuard do
        def f(v) when Regex == Map.get(v, :__struct__), do: :r
        def f(_v), do: :o
      end
      """

      expected = """
      defmodule StructGuard do
        def f(%Regex{} = v), do: :r
        def f(_v), do: :o
      end
      """

      confirm_fix(fix(input), expected)
    end

    # The struct test is lifted out and the rest of the `and` chain stays. `%Regex{} = v`
    # already implies `is_map(v)`, so keeping it is redundant rather than wrong — and
    # dropping conjuncts the rule was not asked about is how guards lose meaning.
    test "an and-chain keeps its other conjuncts" do
      input = """
      defmodule StructGuard do
        def f(v) when is_map(v) and Map.get(v, :__struct__) == Regex, do: :r
        def f(_v), do: :o
      end
      """

      expected = """
      defmodule StructGuard do
        def f(%Regex{} = v) when is_map(v), do: :r
        def f(_v), do: :o
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "a parameter that is not the first one" do
      input = """
      defmodule StructGuard do
        def go(x, re) when Map.get(re, :__struct__) == Regex, do: {:regex_matched, x}
        def go(x, _other), do: {:plain, x}
      end
      """

      expected = """
      defmodule StructGuard do
        def go(x, %Regex{} = re), do: {:regex_matched, x}
        def go(x, _other), do: {:plain, x}
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "a dotted alias" do
      input = """
      defmodule StructGuard do
        def f(v) when Map.get(v, :__struct__) == NaiveDateTime, do: :dt
        def f(_v), do: :o
      end
      """

      expected = """
      defmodule StructGuard do
        def f(%NaiveDateTime{} = v), do: :dt
        def f(_v), do: :o
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "defp" do
      input = """
      defmodule StructGuard do
        defp f(v) when Map.get(v, :__struct__) == Regex, do: :r
        defp f(_v), do: :o
        def call(x), do: f(x)
      end
      """

      expected = """
      defmodule StructGuard do
        defp f(%Regex{} = v), do: :r
        defp f(_v), do: :o
        def call(x), do: f(x)
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # The repair has to do more than parse: it has to compile, and dispatch the way the
  # author evidently meant. The "before" has no runtime behaviour to preserve — it is a
  # hard CompileError — so this is the whole equivalence argument.
  describe "the repaired module compiles and dispatches correctly" do
    test "fixture compilation contains nonterminating top-level code" do
      refute RuleHelpers.compiles?("Enum.flat_map(1..10, &Stream.cycle([&1]))")
    end

    test "the input does not compile and the output does" do
      input = """
      defmodule DispatchCheck do
        def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
        def f(v), do: {:plain, v}
      end
      """

      refute RuleHelpers.compiles?(input)
      assert RuleHelpers.compiles?(fix(input))
    end

    test "only the named struct takes the first clause" do
      input = """
      defmodule DispatchExec do
        def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
        def f(v), do: {:plain, v}
      end
      """

      fixed = fix(input)

      results =
        compile_and_send(fixed, [
          "DispatchExec.f(~r/x/)",
          "DispatchExec.f(%{a: 1})",
          ~s|DispatchExec.f("s")|,
          "DispatchExec.f(1)"
        ])

      assert [{:regex, regex}, {:plain, %{a: 1}}, {:plain, "s"}, {:plain, 1}] = results
      assert Regex.source(regex) == "x"
    end

    test "the and-chain case dispatches correctly too" do
      input = """
      defmodule DispatchConj do
        def f(v) when is_map(v) and Map.get(v, :__struct__) == Regex, do: :r
        def f(_v), do: :o
      end
      """

      fixed = fix(input)

      assert compile_and_send(fixed, [
               "DispatchConj.f(~r/x/)",
               "DispatchConj.f(%{a: 1})",
               "DispatchConj.f(1)"
             ]) == [:r, :o, :o]
    end
  end

  # Each of these is a recorded corruption path, not a missing feature.
  describe "declines, byte for byte" do
    test "a different remote-function diagnostic cannot rewrite quoted data" do
      input = """
      defmodule StructGuardUnrelatedDiagnostic do
        def quoted,
          do: quote(do: (def q(v) when Map.get(v, :__struct__) == Regex, do: v))

        def f(n) when String.length(n) > 0, do: :ok
      end
      """

      assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
      diagnostic = Enum.find(diagnostics, &(&1.severity == :error))
      assert diagnostic.message == "cannot invoke remote function String.length/1 inside a guard"

      confirm_fix(FixStructTestInGuard.fix(input, diagnostic), input)

      map_diagnostic_at_the_error = %{
        diagnostic
        | message: "cannot invoke remote function Map.get/2 inside a guard"
      }

      confirm_fix(FixStructTestInGuard.fix(input, map_diagnostic_at_the_error), input)
    end

    test "an application module aliased as Map is not Elixir's Map" do
      input = """
      defmodule StructGuardAliasedMap do
        alias StructGuardAliasedMap.Custom, as: Map

        defmodule Custom do
          def get(_value, :__struct__), do: Regex
        end

        def f(v) when Map.get(v, :__struct__) == Regex, do: :custom
        def f(_v), do: :fallback
      end
      """

      assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
      diagnostic = Enum.find(diagnostics, &(&1.severity == :error))

      assert diagnostic.message ==
               "cannot invoke remote function StructGuardAliasedMap.Custom.get/2 inside a guard"

      confirm_fix(FixStructTestInGuard.fix(input, diagnostic), input)
    end

    # THE hazard docs/18 records as the hole its proposed containment check does not
    # close. Moving `%Regex{}` onto `%{} = re` would REPLACE the pattern rather than
    # intersect with it, and the guard is gone, so the clause matches every map.
    # Executed on the naive output: `go("x", %{a: 1})` gave `{:regex_matched, "x"}`.
    test "the parameter is already a map pattern" do
      input = """
      defmodule StructGuard do
        def go(x, %{} = re) when Map.get(re, :__struct__) == Regex, do: {:regex_matched, x}
        def go(x, _other), do: {:plain, x}
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the parameter is a list pattern" do
      input = """
      defmodule StructGuard do
        def go(x, [_ | _] = re) when Map.get(re, :__struct__) == Regex, do: {:matched, x}
        def go(x, _other), do: {:plain, x}
      end
      """

      confirm_fix(fix(input), input)
    end

    # Removing one side of an `or` changes which values reach the clause, and an `or`
    # guard is exactly where docs/17's path (b) deleted a clause outright.
    test "an or guard anywhere in the guard" do
      input = """
      defmodule StructGuard do
        def f(v) when is_nil(v) or Map.get(v, :__struct__) == Regex, do: :r
        def f(_v), do: :o
      end
      """

      confirm_fix(fix(input), input)
    end

    # These need the test moved into the BODY, and the body is what docs/17's three
    # corruption paths make unsafe. They stay banked.
    for {label, guard, message} <- [
          {"a length test", "String.length(n) > 0", "String.length/1"},
          {"a key test", "Map.has_key?(n, :k)", "Map.has_key?/2"},
          {"an arithmetic test", "System.monotonic_time(:millisecond) - 1 >= 2",
           "System.monotonic_time/1"}
        ] do
      test "#{label}, whose only repair would be the body hoist" do
        input = """
        defmodule StructGuard do
          def f(n) when #{unquote(guard)}, do: :ok
          def f(_n), do: :other
        end
        """

        confirm_fix(
          fix(input, "cannot invoke remote function #{unquote(message)} inside a guard"),
          input
        )
      end
    end

    test "a guard with two struct tests, where which one to lift is ambiguous" do
      input = """
      defmodule StructGuard do
        def f(a, b) when Map.get(a, :__struct__) == Regex and Map.get(b, :__struct__) == Date,
          do: :both

        def f(_a, _b), do: :o
      end
      """

      confirm_fix(fix(input), input)
    end

    test "a clause with no guard" do
      input = """
      defmodule StructGuard do
        def f(v), do: v
      end
      """

      confirm_fix(fix(input), input)
    end

    test "a struct test that is already in the pattern" do
      input = """
      defmodule StructGuard do
        def f(%Regex{} = v), do: v
      end
      """

      confirm_fix(fix(input), input)
    end

    test "source that does not parse" do
      input = """
      defmodule StructGuard do
        def f(v) when , do: v
      """

      confirm_fix(fix(input), input)
    end
  end

  # The self-corruption oracle's question, asked directly for a Semantic rule: it has no
  # `fix/1`, so the Syntax-round oracle cannot see it.
  describe "cannot corrupt the tree" do
    test "no file in lib/ is altered" do
      altered =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.filter(fn path ->
          source = File.read!(path)
          fix(source) != source
        end)

      assert altered == []
    end
  end
end
