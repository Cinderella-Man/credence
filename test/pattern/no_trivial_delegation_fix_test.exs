defmodule Credence.Pattern.NoTrivialDelegationFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoTrivialDelegation

  # ═══════════════════════════════════════════════════════════════════
  # REWRITES — inline the stdlib call, delete the wrapper
  # ═══════════════════════════════════════════════════════════════════

  describe "inlines the wrapper at its call sites" do
    test "single call site, String.length/1" do
      code = """
      defmodule M do
        defp string_length(str), do: String.length(str)

        def run(s), do: string_length(s)
      end
      """

      expected = """
      defmodule M do
        def run(s), do: String.length(s)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), expected)
    end

    test "multiple call sites, Enum.count/1" do
      code = """
      defmodule M do
        defp count_items(list), do: Enum.count(list)

        def a(l), do: count_items(l)
        def b(l), do: count_items(l) + 1
      end
      """

      expected = """
      defmodule M do
        def a(l), do: Enum.count(l)
        def b(l), do: Enum.count(l) + 1
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), expected)
    end

    test "Kernel.length/1 stays a local call" do
      code = """
      defmodule M do
        defp list_len(l), do: length(l)

        def run(l), do: list_len(l)
      end
      """

      expected = """
      defmodule M do
        def run(l), do: length(l)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), expected)
    end

    test "multi-arg wrapper, Map.get/2" do
      code = """
      defmodule M do
        defp fetch(m, k), do: Map.get(m, k)

        def run(m, k), do: fetch(m, k)
      end
      """

      expected = """
      defmodule M do
        def run(m, k), do: Map.get(m, k)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — shapes check/2 deliberately does not flag
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves unsafe / out-of-scope shapes untouched" do
    test "reordered args" do
      code = """
      defmodule M do
        defp my_join(list, sep), do: Enum.join(sep, list)

        def run(l, s), do: my_join(l, s)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "public function" do
      code = """
      defmodule M do
        def string_length(str), do: String.length(str)

        def run(s), do: string_length(s)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "wrapper with a guard" do
      code = """
      defmodule M do
        defp count_items(list) when is_list(list), do: Enum.count(list)

        def run(l), do: count_items(l)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "wrapper with multiple clauses" do
      code = """
      defmodule M do
        defp first([]), do: Enum.reverse([])
        defp first(list), do: Enum.reverse(list)

        def run(l), do: first(l)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "captured wrapper" do
      code = """
      defmodule M do
        def process(list) do
          Enum.map(list, &sum_items/1)
        end

        defp sum_items(items), do: Enum.sum(items)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "piped call with an elided argument" do
      code = """
      defmodule M do
        defp count_items(list), do: Enum.count(list)

        def run(l), do: l |> count_items()
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "name appears as a bare atom (apply/3)" do
      code = """
      defmodule M do
        defp string_length(str), do: String.length(str)

        def run(s), do: apply(__MODULE__, :string_length, [s])
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end

    test "local-call wrapper sharing a Kernel name (recursion)" do
      code = """
      defmodule M do
        defp length(l), do: length(l)

        def run(l), do: length(l)
      end
      """

      confirm_fix(fix(NoTrivialDelegation, code), code)
    end
  end
end
