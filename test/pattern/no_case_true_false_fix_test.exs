defmodule Credence.Pattern.NoCaseTrueFalseFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NoCaseTrueFalse.fix(code, [])
  end

  # Helper: normalise whitespace for structural comparison
  defp normalize(code) do
    code |> String.trim() |> String.replace(~r/\s+/, " ")
  end

  # ═══════════════════════════════════════════════════════════════════
  # TRUE / FALSE — standard rewrite
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites case true/false to if/else" do
    test "simple true then false" do
      input = """
      case x > 0 do
        true -> :positive
        false -> :non_positive
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert fixed =~ "if"
      assert fixed =~ "else"
      assert fixed =~ ":positive"
      assert fixed =~ ":non_positive"
      # true body is in the do block
      assert normalize(fixed) =~ "if x > 0 do :positive else :non_positive end"
    end

    test "flipped false then true" do
      input = """
      case x > 0 do
        false -> :non_positive
        true -> :positive
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      # Bodies must be swapped: true body in do, false body in else
      assert normalize(fixed) =~ "if x > 0 do :positive else :non_positive end"
    end

    test "complex expression in subject" do
      input = """
      case rem(total_count, 2) == 0 do
        true -> (a + b) / 2.0
        false -> mid
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert fixed =~ "if"
      assert fixed =~ "rem(total_count, 2) == 0"
      assert fixed =~ "(a + b) / 2.0"
      assert fixed =~ "mid"
    end

    test "multi-line bodies" do
      input = """
      case Map.has_key?(map, key) do
        true ->
          value = Map.get(map, key)
          {:ok, value}
        false ->
          {:error, :not_found}
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert fixed =~ "if"
      assert fixed =~ "Map.get(map, key)"
      assert fixed =~ "{:ok, value}"
      assert fixed =~ "{:error, :not_found}"
    end

    test "function call as subject" do
      input = """
      case String.contains?(input, "needle") do
        true -> :found
        false -> :not_found
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert fixed =~ ~s[if String.contains?(input, "needle")]
    end

    test "nested inside a def" do
      input = """
      defmodule Example do
        def run(n) do
          case n > 10 do
            true -> :big
            false -> :small
          end
        end
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert fixed =~ "if n > 10 do"
      assert fixed =~ "defmodule Example"
      assert fixed =~ "def run(n)"
    end

    test "fixes multiple occurrences" do
      input = """
      defmodule Example do
        def foo(x) do
          case x > 0 do
            true -> :pos
            false -> :neg
          end
        end

        def bar(x) do
          case x == 0 do
            true -> :zero
            false -> :nonzero
          end
        end
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert fixed =~ "if x > 0 do"
      assert fixed =~ "if x == 0 do"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # WILDCARD VARIANT — true / _
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites case true/_ to if/else" do
    test "true then wildcard" do
      input = """
      case x > 0 do
        true -> :positive
        _ -> :non_positive
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      assert normalize(fixed) =~ "if x > 0 do :positive else :non_positive end"
    end

    test "false then wildcard" do
      input = """
      case x > 0 do
        false -> :non_positive
        _ -> :positive
      end
      """

      fixed = fix(input)
      refute fixed =~ "case"
      # false body goes to else, wildcard body goes to do
      assert normalize(fixed) =~ "if x > 0 do :positive else :non_positive end"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT touch
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify legitimate case statements" do
    test "case on atoms" do
      input = """
      case result do
        :ok -> handle_ok()
        :error -> handle_error()
      end
      """

      assert fix(input) == input
    end

    test "case with pattern matching" do
      input = """
      case list do
        [] -> :empty
        [_ | _] -> :non_empty
      end
      """

      assert fix(input) == input
    end

    test "case with tuple patterns" do
      input = """
      case File.read(path) do
        {:ok, content} -> content
        {:error, reason} -> raise reason
      end
      """

      assert fix(input) == input
    end

    test "case with three clauses" do
      input = """
      case status do
        true -> :yes
        false -> :no
        nil -> :unknown
      end
      """

      assert fix(input) == input
    end

    test "case with guards" do
      input = """
      case x do
        n when n > 0 -> :positive
        n when n < 0 -> :negative
      end
      """

      assert fix(input) == input
    end

    test "already an if/else" do
      input = """
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """

      assert fix(input) == input
    end

    test "returns source unchanged when nothing to fix" do
      input = """
      defmodule Example do
        def run(n), do: n * 2
      end
      """

      assert fix(input) == input
    end
  end
end
