defmodule Credence.Pattern.NoListToTupleForAccessFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListToTupleForAccess

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListToTupleForAccess.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoListToTupleForAccess, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix/2" do
    test "converts direct List.to_tuple + elem to Enum.at, dropping the dead binding" do
      input = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          elem(t, 0)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          Enum.at(list, 0)
        end
      end
      """

      assert fix(input) == expected
    end

    test "converts piped List.to_tuple + elem to Enum.at, dropping the dead binding" do
      input = """
      defmodule Example do
        def run(list) do
          t = list |> List.to_tuple()
          elem(t, 0)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          Enum.at(list, 0)
        end
      end
      """

      assert fix(input) == expected
    end

    test "converts multiple elem calls and drops the now-unused binding" do
      input = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          a = elem(t, 0)
          b = elem(t, 1)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          {a, b}
        end
      end
      """

      assert fix(input) == expected
    end

    test "leaves List.to_tuple binding when t is still used elsewhere" do
      input = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          size = tuple_size(t)
          first = elem(t, 0)
          {first, size}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          size = tuple_size(t)
          first = Enum.at(list, 0)
          {first, size}
        end
      end
      """

      assert fix(input) == expected
    end

    test "returns source unchanged when no List.to_tuple bindings found" do
      code = """
      defmodule Example do
        def run(list) do
          List.to_tuple(list)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not touch elem on a variable not from List.to_tuple" do
      code = """
      defmodule Example do
        def run(tuple) do
          elem(tuple, 0)
        end
      end
      """

      assert fix(code) == code
    end

    test "handles long pipeline ending with List.to_tuple" do
      input = """
      defmodule Example do
        def run(str) do
          t =
            str
            |> String.trim()
            |> String.upcase()
            |> List.to_tuple()

          elem(t, 0)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(str) do
          Enum.at(
            str
            |> String.trim()
            |> String.upcase(),
            0
          )
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/2 — loop-scope safety (issue: perf regression + dead code)" do
    test "does not rewrite elem inside an Enum.reduce lambda" do
      input = """
      defmodule Demo do
        def f(coords, indices) do
          coords_tuple = List.to_tuple(coords)

          Enum.reduce(indices, [], fn idx, acc ->
            {x, y} = elem(coords_tuple, idx)
            [{x, y} | acc]
          end)
        end
      end
      """

      assert fix(input) == input
      assert check(input) == []
    end

    test "does not rewrite elem inside a for comprehension" do
      input = """
      defmodule Demo do
        def f(list, idxs) do
          t = List.to_tuple(list)
          for i <- idxs, do: elem(t, i)
        end
      end
      """

      assert fix(input) == input
      assert check(input) == []
    end

    test "does not rewrite elem inside Enum.map lambda" do
      input = """
      defmodule Demo do
        def f(list, idxs) do
          t = List.to_tuple(list)
          Enum.map(idxs, fn i -> elem(t, i) end)
        end
      end
      """

      assert fix(input) == input
      assert check(input) == []
    end

    test "removes the dead List.to_tuple binding when its only reader is a fixed elem call" do
      input = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          elem(t, 0)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          Enum.at(list, 0)
        end
      end
      """

      assert fix(input) == expected
    end

    test "removes the dead binding when all elem readers are out-of-loop and rewritten" do
      input = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          a = elem(t, 0)
          b = elem(t, 1)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          {a, b}
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves binding when a non-elem reader (e.g. tuple_size) remains" do
      input = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          size = tuple_size(t)
          first = elem(t, 0)
          {first, size}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          t = List.to_tuple(list)
          size = tuple_size(t)
          first = Enum.at(list, 0)
          {first, size}
        end
      end
      """

      assert fix(input) == expected
    end
  end
end
