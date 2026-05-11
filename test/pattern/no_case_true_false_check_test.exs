defmodule Credence.Pattern.NoCaseTrueFalseCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoCaseTrueFalse.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case true/false" do
    test "simple true then false" do
      assert flagged?("""
      case x > 0 do
        true -> :positive
        false -> :non_positive
      end
      """)
    end

    test "simple false then true (flipped)" do
      assert flagged?("""
      case x > 0 do
        false -> :non_positive
        true -> :positive
      end
      """)
    end

    test "complex expression in case subject" do
      assert flagged?("""
      case rem(total_count, 2) == 0 do
        true -> (a + b) / 2.0
        false -> a / 1.0
      end
      """)
    end

    test "multi-line bodies" do
      assert flagged?("""
      case Map.has_key?(map, key) do
        true ->
          value = Map.get(map, key)
          {:ok, value}
        false ->
          {:error, :not_found}
      end
      """)
    end

    test "function call as subject" do
      assert flagged?("""
      case String.contains?(input, "needle") do
        true -> :found
        false -> :not_found
      end
      """)
    end

    test "inline case" do
      assert flagged?(~S"case is_nil(x) do true -> 0; false -> x end")
    end

    test "nested inside a def" do
      assert flagged?("""
      defmodule Example do
        def run(n) do
          case n > 10 do
            true -> :big
            false -> :small
          end
        end
      end
      """)
    end

    test "flags multiple occurrences" do
      code = """
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

      assert length(check(code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # WILDCARD VARIANT — true / _
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case true/_ variant" do
    test "true then wildcard" do
      assert flagged?("""
      case x > 0 do
        true -> :positive
        _ -> :non_positive
      end
      """)
    end

    test "wildcard then true (flipped)" do
      assert flagged?("""
      case x > 0 do
        _ -> :non_positive
        true -> :positive
      end
      """)
    end

    test "false then wildcard" do
      assert flagged?("""
      case x > 0 do
        false -> :non_positive
        _ -> :positive
      end
      """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag legitimate case statements" do
    test "case on atoms" do
      assert clean?("""
      case result do
        :ok -> handle_ok()
        :error -> handle_error()
      end
      """)
    end

    test "case with pattern matching" do
      assert clean?("""
      case list do
        [] -> :empty
        [_ | _] -> :non_empty
      end
      """)
    end

    test "case with tuple patterns" do
      assert clean?("""
      case File.read(path) do
        {:ok, content} -> content
        {:error, reason} -> raise reason
      end
      """)
    end

    test "case with three clauses including true and false" do
      assert clean?("""
      case status do
        true -> :yes
        false -> :no
        nil -> :unknown
      end
      """)
    end

    test "case with guards on clauses" do
      assert clean?("""
      case x do
        n when n > 0 -> :positive
        n when n < 0 -> :negative
      end
      """)
    end

    test "case with single clause" do
      assert clean?("""
      case x do
        true -> :yes
      end
      """)
    end

    test "existing if/else is not flagged" do
      assert clean?("""
      if x > 0 do
        :positive
      else
        :non_positive
      end
      """)
    end

    test "case on variable (not boolean expression)" do
      # This matches on true/false but the subject is a plain variable,
      # which is a legitimate pattern match on a boolean value.
      # Depending on design choice, this could be flagged or not.
      # Including as clean for now — revisit if desired.
      assert clean?("""
      case some_flag do
        true -> :enabled
        false -> :disabled
      end
      """)
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoCaseTrueFalse.fixable?() == true
    end
  end
end
