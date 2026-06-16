defmodule Credence.Pattern.NoCaseTrueFalseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCaseTrueFalse

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

      expected = """
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end

    test "flipped false then true" do
      input = """
      case x > 0 do
        false -> :non_positive
        true -> :positive
      end
      """

      expected = """
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end

    test "complex expression in subject" do
      input = """
      case rem(total_count, 2) == 0 do
        true -> (a + b) / 2.0
        false -> mid
      end
      """

      expected = """
      if rem(total_count, 2) == 0 do
        (a + b) / 2.0
      else
        mid
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
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

      expected = """
      if Map.has_key?(map, key) do
        value = Map.get(map, key)
        {:ok, value}
      else
        {:error, :not_found}
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end

    test "function call as subject" do
      input = """
      case String.contains?(input, "needle") do
        true -> :found
        false -> :not_found
      end
      """

      expected = """
      if String.contains?(input, "needle") do
        :found
      else
        :not_found
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
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

      expected = """
      defmodule Example do
        def run(n) do
          if n > 10 do
            :big
          else
            :small
          end
        end
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
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

      expected = """
      defmodule Example do
        def foo(x) do
          if x > 0 do
            :pos
          else
            :neg
          end
        end

        def bar(x) do
          if x == 0 do
            :zero
          else
            :nonzero
          end
        end
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
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

      expected = """
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end

    test "false then wildcard" do
      input = """
      case x > 0 do
        false -> :non_positive
        _ -> :positive
      end
      """

      expected = """
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PIPED CASE — expr |> case do true/false end
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites piped case true/false to if/else" do
    test "simple pipe into case true/false" do
      input = """
      valid_digits?()
      |> case do
        true -> :ok
        false -> :error
      end
      """

      expected = """
      if valid_digits?() do
        :ok
      else
        :error
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end

    test "pipe chain into case true/false" do
      input = """
      number
      |> Integer.digits()
      |> valid_digits?()
      |> case do
        true -> rotated_number != number
        false -> false
      end
      """

      expected = """
      if number
         |> Integer.digits()
         |> valid_digits?() do
        rotated_number != number
      else
        false
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
    end

    test "pipe into case with flipped false/true" do
      input = """
      check(x)
      |> case do
        false -> :error
        true -> :ok
      end
      """

      expected = """
      if check(x) do
        :ok
      else
        :error
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), expected)
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

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "case with pattern matching" do
      input = """
      case list do
        [] -> :empty
        [_ | _] -> :non_empty
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "case with tuple patterns" do
      input = """
      case File.read(path) do
        {:ok, content} -> content
        {:error, reason} -> raise reason
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "case with three clauses" do
      input = """
      case status do
        true -> :yes
        false -> :no
        nil -> :unknown
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "case with guards" do
      input = """
      case x do
        n when n > 0 -> :positive
        n when n < 0 -> :negative
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "already an if/else" do
      input = """
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "returns source unchanged when nothing to fix" do
      input = """
      defmodule Example do
        def run(n), do: n * 2
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end

    test "piped case on a plain variable is not modified" do
      # A plain variable on the left of the pipe may be a tristate pattern
      # match, which `if` would not preserve; leave it untouched.
      input = """
      some_flag
      |> case do
        true -> :enabled
        false -> :disabled
      end
      """

      confirm_fix(fix(NoCaseTrueFalse, input), input)
    end
  end
end
