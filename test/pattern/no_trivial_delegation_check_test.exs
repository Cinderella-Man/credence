defmodule Credence.Pattern.NoTrivialDelegationCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoTrivialDelegation

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoTrivialDelegation.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD FLAG — trivial wrappers around standard library functions
  # ═══════════════════════════════════════════════════════════════════

  describe "flags trivial delegation to String.length/1" do
    test "single-arg wrapper" do
      assert flagged?("""
             defmodule M do
               defp string_length(str), do: String.length(str)

               def run(s), do: string_length(s)
             end
             """)
    end

    test "multi-line do/end form" do
      assert flagged?("""
             defmodule M do
               defp string_length(str) do
                 String.length(str)
               end

               def run(s), do: string_length(s)
             end
             """)
    end
  end

  describe "flags trivial delegation to Enum.count/1" do
    test "single-arg wrapper" do
      assert flagged?("""
             defmodule M do
               defp count_items(list), do: Enum.count(list)

               def run(l), do: count_items(l)
             end
             """)
    end
  end

  describe "flags trivial delegation to Map.size/1" do
    test "single-arg wrapper" do
      assert flagged?("""
             defmodule M do
               defp map_size(m), do: Map.size(m)

               def run(m), do: map_size(m)
             end
             """)
    end
  end

  describe "flags trivial delegation to Kernel.length/1" do
    test "single-arg wrapper" do
      assert flagged?("""
             defmodule M do
               defp list_len(l), do: length(l)

               def run(l), do: list_len(l)
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — non-trivial wrappers
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when args are reordered" do
    test "swapped args" do
      assert clean?("""
             defmodule M do
               defp my_join(list, sep), do: Enum.join(sep, list)

               def run(l, s), do: my_join(l, s)
             end
             """)
    end
  end

  describe "does not flag when args are transformed" do
    test "wrapped arg" do
      assert clean?("""
             defmodule M do
               defp string_length(x), do: String.length(to_string(x))

               def run(x), do: string_length(x)
             end
             """)
    end
  end

  describe "does not flag delegation to non-stdlib functions" do
    test "local function delegation" do
      assert clean?("""
             defmodule M do
               defp my_helper(x), do: other_module_func(x)

               def run(x), do: my_helper(x)
             end
             """)
    end

    test "project module delegation" do
      assert clean?("""
             defmodule M do
               defp process(x), do: MyProject.Processor.run(x)

               def run(x), do: process(x)
             end
             """)
    end
  end

  describe "does not flag when body is more than a single call" do
    test "body has multiple expressions" do
      assert clean?("""
             defmodule M do
               defp string_length(str) do
                 result = String.length(str)
                 result + 1
               end

               def run(s), do: string_length(s)
             end
             """)
    end
  end

  describe "does not flag when wrapper arity does not match" do
    test "extra args" do
      assert clean?("""
             defmodule M do
               defp string_length(str, _opts), do: String.length(str)

               def run(s), do: string_length(s, [])
             end
             """)
    end
  end

  describe "does not flag non-defp functions" do
    test "public function delegation" do
      assert clean?("""
             defmodule M do
               def string_length(str), do: String.length(str)

               def run(s), do: string_length(s)
             end
             """)
    end
  end

  describe "does not flag when defp is used as function reference" do
    test "capture reference &name/arity" do
      assert clean?("""
             defmodule M do
               def process(list) do
                 list |> Enum.map(&sum_items/1)
               end

               defp sum_items(items), do: Enum.sum(items)
             end
             """)
    end

    test "capture reference in Stream.map" do
      assert clean?("""
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
end
