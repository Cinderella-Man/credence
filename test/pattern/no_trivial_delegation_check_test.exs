defmodule Credence.Pattern.NoTrivialDelegationCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoTrivialDelegation

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD FLAG — trivial wrappers with an inlinable call site
  # ═══════════════════════════════════════════════════════════════════

  describe "flags trivial delegation to a stdlib function" do
    test "String.length/1, do: form" do
      assert flagged?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str), do: String.length(str)

               def run(s), do: string_length(s)
             end
             """)
    end

    test "String.length/1, multi-line do/end form" do
      assert flagged?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str) do
                 String.length(str)
               end

               def run(s), do: string_length(s)
             end
             """)
    end

    test "Enum.count/1" do
      assert flagged?(NoTrivialDelegation, """
             defmodule M do
               defp count_items(list), do: Enum.count(list)

               def run(l), do: count_items(l)
             end
             """)
    end

    test "Kernel.length/1 as a local call" do
      assert flagged?(NoTrivialDelegation, """
             defmodule M do
               defp list_len(l), do: length(l)

               def run(l), do: list_len(l)
             end
             """)
    end

    test "multi-arg Map.get/2" do
      assert flagged?(NoTrivialDelegation, """
             defmodule M do
               defp fetch(m, k), do: Map.get(m, k)

               def run(m, k), do: fetch(m, k)
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — not a trivial passthrough
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag non-passthrough bodies" do
    test "reordered args" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp my_join(list, sep), do: Enum.join(sep, list)

               def run(l, s), do: my_join(l, s)
             end
             """)
    end

    test "transformed arg" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(x), do: String.length(to_string(x))

               def run(x), do: string_length(x)
             end
             """)
    end

    test "more than a single call in the body" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str) do
                 result = String.length(str)
                 result + 1
               end

               def run(s), do: string_length(s)
             end
             """)
    end

    test "wrapper arity does not match the wrapped function" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str, _opts), do: String.length(str)

               def run(s), do: string_length(s, [])
             end
             """)
    end
  end

  describe "does not flag delegation to non-stdlib functions" do
    test "local function delegation" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp my_helper(x), do: other_module_func(x)

               def run(x), do: my_helper(x)
             end
             """)
    end

    test "project module delegation" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp process(x), do: MyProject.Processor.run(x)

               def run(x), do: process(x)
             end
             """)
    end
  end

  describe "does not flag public functions" do
    test "def, not defp" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               def string_length(str), do: String.length(str)

               def run(s), do: string_length(s)
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — deliberately dropped unsafe-to-inline shapes
  # (the rule only flags what the fix can safely rewrite)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when the wrapper is used as a function reference" do
    test "captured with &name/arity" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               def process(list) do
                 Enum.map(list, &sum_items/1)
               end

               defp sum_items(items), do: Enum.sum(items)
             end
             """)
    end

    test "captured in Stream.map" do
      assert clean?(NoTrivialDelegation, """
             defmodule BatchProcessor do
               def process_in_batches(stream, batch_size) do
                 stream
                 |> Stream.chunk_every(batch_size)
                 |> Stream.map(&process_batch/1)
                 |> Enum.to_list()
               end

               defp process_batch(batch), do: Enum.sum(batch)
             end
             """)
    end
  end

  describe "does not flag when the rewrite cannot be proven safe" do
    test "wrapper has a guard (drops an admitted-input check)" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp count_items(list) when is_list(list), do: Enum.count(list)

               def run(l), do: count_items(l)
             end
             """)
    end

    test "wrapper has multiple clauses to dispatch on" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp first([]), do: Enum.reverse([])
               defp first(list), do: Enum.reverse(list)

               def run(l), do: first(l)
             end
             """)
    end

    test "no call site to inline" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str), do: String.length(str)
             end
             """)
    end

    test "call site is a piped call with an elided argument" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp count_items(list), do: Enum.count(list)

               def run(l), do: l |> count_items()
             end
             """)
    end

    test "name appears as a bare atom (e.g. apply/3)" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str), do: String.length(str)

               def run(s), do: apply(__MODULE__, :string_length, [s])
             end
             """)
    end

    test "name is also used as a variable" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp string_length(str), do: String.length(str)

               def run(s) do
                 string_length = String.length(s)
                 string_length(s) + string_length
               end
             end
             """)
    end

    test "local-call wrapper sharing a Kernel name is recursion, not delegation" do
      assert clean?(NoTrivialDelegation, """
             defmodule M do
               defp length(l), do: length(l)

               def run(l), do: length(l)
             end
             """)
    end
  end
end
