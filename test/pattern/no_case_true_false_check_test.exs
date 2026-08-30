defmodule Credence.Pattern.NoCaseTrueFalseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCaseTrueFalse

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case true/false" do
    test "simple true then false" do
      assert flagged?(NoCaseTrueFalse, """
             case x > 0 do
               true -> :positive
               false -> :non_positive
             end
             """)
    end

    test "simple false then true (flipped)" do
      assert flagged?(NoCaseTrueFalse, """
             case x > 0 do
               false -> :non_positive
               true -> :positive
             end
             """)
    end

    test "complex expression in case subject" do
      assert flagged?(NoCaseTrueFalse, """
             case rem(total_count, 2) == 0 do
               true -> (a + b) / 2.0
               false -> a / 1.0
             end
             """)
    end

    test "multi-line bodies" do
      assert flagged?(NoCaseTrueFalse, """
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
      assert flagged?(NoCaseTrueFalse, """
             case String.contains?(input, "needle") do
               true -> :found
               false -> :not_found
             end
             """)
    end

    test "inline case" do
      assert flagged?(NoCaseTrueFalse, "case is_nil(x) do true -> 0; false -> x end")
    end

    test "nested inside a def" do
      assert flagged?(NoCaseTrueFalse, """
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

      assert length(check(NoCaseTrueFalse, code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # WILDCARD VARIANT — true / _
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case true/_ variant" do
    test "true then wildcard" do
      assert flagged?(NoCaseTrueFalse, """
             case x > 0 do
               true -> :positive
               _ -> :non_positive
             end
             """)
    end

    test "false then wildcard" do
      assert flagged?(NoCaseTrueFalse, """
             case x > 0 do
               false -> :non_positive
               _ -> :positive
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PIPED CASE — expr |> case do true/false end
  # ═══════════════════════════════════════════════════════════════════

  describe "flags piped case true/false" do
    test "simple pipe into case true/false" do
      assert flagged?(NoCaseTrueFalse, """
             is_list([])
             |> case do
               true -> :ok
               false -> :error
             end
             """)
    end

    test "pipe chain into case true/false" do
      assert flagged?(NoCaseTrueFalse, """
             number
             |> Integer.digits()
             |> Enum.empty?()
             |> case do
               true -> :valid
               false -> :invalid
             end
             """)
    end

    test "pipe into case with multi-line true body" do
      assert flagged?(NoCaseTrueFalse, """
             is_list(x)
             |> case do
               true ->
                 value = process(x)
                 {:ok, value}
               false ->
                 {:error, :failed}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag legitimate case statements" do
    test "and/or expressions and predicate names do not prove a boolean result" do
      assert clean?(NoCaseTrueFalse, "case true and :unknown do true -> :yes; false -> :no end")
      assert clean?(NoCaseTrueFalse, "case false or :unknown do true -> :yes; false -> :no end")
      assert clean?(NoCaseTrueFalse, "case ready?() do true -> :yes; false -> :no end")
    end

    # Wildcard FIRST makes the second clause unreachable, so the case yields
    # `:non_positive` for every subject. No `if` preserves that except
    # `if x > 0, do: :non_positive, else: :non_positive`, and the readable-looking
    # rewrite would change behaviour — so the fix declines, and after sharing one
    # predicate the check declines too. It used to report this and leave it
    # unrepaired.
    test "wildcard first, which makes the true clause unreachable" do
      assert clean?(NoCaseTrueFalse, """
             case x > 0 do
               _ -> :non_positive
               true -> :positive
             end
             """)
    end

    test "wildcard first, with false second" do
      assert clean?(NoCaseTrueFalse, """
             case x > 0 do
               _ -> :positive
               false -> :non_positive
             end
             """)
    end

    test "case on atoms" do
      assert clean?(NoCaseTrueFalse, """
             case result do
               :ok -> handle_ok()
               :error -> handle_error()
             end
             """)
    end

    test "case with pattern matching" do
      assert clean?(NoCaseTrueFalse, """
             case list do
               [] -> :empty
               [_ | _] -> :non_empty
             end
             """)
    end

    test "case with tuple patterns" do
      assert clean?(NoCaseTrueFalse, """
             case File.read(path) do
               {:ok, content} -> content
               {:error, reason} -> raise reason
             end
             """)
    end

    test "case with three clauses including true and false" do
      assert clean?(NoCaseTrueFalse, """
             case status do
               true -> :yes
               false -> :no
               nil -> :unknown
             end
             """)
    end

    test "case with guards on clauses" do
      assert clean?(NoCaseTrueFalse, """
             case x do
               n when n > 0 -> :positive
               n when n < 0 -> :negative
             end
             """)
    end

    test "case with single clause" do
      assert clean?(NoCaseTrueFalse, """
             case x do
               true -> :yes
             end
             """)
    end

    test "existing if/else is not flagged" do
      assert clean?(NoCaseTrueFalse, """
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
      assert clean?(NoCaseTrueFalse, """
             case some_flag do
               true -> :enabled
               false -> :disabled
             end
             """)
    end

    test "piped case on a plain variable is not flagged" do
      # Same safety choice as the direct form: a plain variable on the left of
      # the pipe may be a tristate pattern match, which `if` would not preserve.
      # The fix already declines this case, so the check must not flag it.
      assert clean?(NoCaseTrueFalse, """
             some_flag
             |> case do
               true -> :enabled
               false -> :disabled
             end
             """)
    end
  end
end
