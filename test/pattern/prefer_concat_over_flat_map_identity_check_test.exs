defmodule Credence.Pattern.PreferConcatOverFlatMapIdentityCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferConcatOverFlatMapIdentity

  describe "check/2 — detects identity flat_map" do
    test "flags Enum.flat_map with fn x -> x end" do
      code = """
      defmodule Example do
        def flatten(matrix), do: Enum.flat_map(matrix, fn row -> row end)
      end
      """

      [issue] = check(PreferConcatOverFlatMapIdentity, code)
      assert issue.rule == :prefer_concat_over_flat_map_identity
      assert issue.message =~ "Enum.concat"
    end

    test "flags piped form with identity fn" do
      code = """
      defmodule Example do
        def flatten(matrix), do: matrix |> Enum.flat_map(fn row -> row end)
      end
      """

      [issue] = check(PreferConcatOverFlatMapIdentity, code)
      assert issue.rule == :prefer_concat_over_flat_map_identity
    end

    test "flags & &1 capture" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, & &1)
      end
      """

      [issue] = check(PreferConcatOverFlatMapIdentity, code)
      assert issue.rule == :prefer_concat_over_flat_map_identity
    end

    test "flags piped & &1" do
      code = """
      defmodule Example do
        def flatten(list), do: list |> Enum.flat_map(& &1)
      end
      """

      [issue] = check(PreferConcatOverFlatMapIdentity, code)
      assert issue.rule == :prefer_concat_over_flat_map_identity
    end

    test "flags with long variable name" do
      code = """
      defmodule Example do
        def flatten(items), do: items |> Enum.flat_map(fn sublist -> sublist end)
      end
      """

      [issue] = check(PreferConcatOverFlatMapIdentity, code)
      assert issue.rule == :prefer_concat_over_flat_map_identity
    end

    test "flags inside a pipeline" do
      code = """
      defmodule Example do
        def flatten(matrix) do
          matrix |> Enum.flat_map(fn row -> row end)
        end
      end
      """

      [issue] = check(PreferConcatOverFlatMapIdentity, code)
      assert issue.rule == :prefer_concat_over_flat_map_identity
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag Enum.concat (already simplified)" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.concat(list)
      end
      """

      assert check(PreferConcatOverFlatMapIdentity, code) == []
    end

    test "does not flag non-identity function" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, fn x -> [x] end)
      end
      """

      assert check(PreferConcatOverFlatMapIdentity, code) == []
    end

    test "does not flag flat_map with a transformation" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, fn x -> String.split(x) end)
      end
      """

      assert check(PreferConcatOverFlatMapIdentity, code) == []
    end

    test "does not flag flat_map with field access" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, & &1.items)
      end
      """

      assert check(PreferConcatOverFlatMapIdentity, code) == []
    end

    test "does not flag fn with different variables in arg and body" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, fn x -> y end)
      end
      """

      assert check(PreferConcatOverFlatMapIdentity, code) == []
    end

    test "does not flag multi-clause fn" do
      code = """
      defmodule Example do
        def flatten(list) do
          Enum.flat_map(list, fn
            nil -> []
            x -> x
          end)
        end
      end
      """

      assert check(PreferConcatOverFlatMapIdentity, code) == []
    end
  end

  # ── &Function.identity/1 (clauses that were unreachable until 2026-08-16) ──
  #
  # The matcher had these two clauses all along, written as two-tuples
  # (`{:&, [...]}`, `{:__aliases__, [:Function]}`) where the AST nodes are
  # three-tuples carrying metadata. Valid Elixir, so nothing warned; no test
  # covered the shape, so the rule silently missed it while its sibling
  # `no_identity_enum_map` caught the identical form on `Enum.map`.

  describe "&Function.identity/1" do
    test "direct call" do
      assert flagged?(PreferConcatOverFlatMapIdentity, """
             defmodule M do
               def f(l), do: Enum.flat_map(l, &Function.identity/1)
             end
             """)
    end

    test "piped" do
      assert flagged?(PreferConcatOverFlatMapIdentity, """
             defmodule M do
               def f(l), do: l |> Enum.flat_map(&Function.identity/1)
             end
             """)
    end

    # The control: a capture that is NOT identity must stay unflagged, so the
    # newly-reachable clauses did not simply widen the rule to every capture.
    test "CONTROL: a different captured function is not identity" do
      assert clean?(PreferConcatOverFlatMapIdentity, """
             defmodule M do
               def f(l), do: Enum.flat_map(l, &List.wrap/1)
             end
             """)
    end
  end
end
