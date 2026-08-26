defmodule Credence.Semantic.NoStringReplaceArityMismatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, compiles?: 1, valid_syntax?: 1]

  alias Credence.Semantic.NoStringReplaceArityMismatch

  @real_message "no function clause matching in String.replace/4"

  defp fix(source, message \\ @real_message, line \\ 0) do
    NoStringReplaceArityMismatch.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  describe "rewrites String.replace/3 to Regex.replace/3" do
    test "rewrites only the call on a positive diagnostic line and leaves quoted code alone" do
      input = """
      defmodule PositionScopedStringReplace do
        @broken String.replace("ab", ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
        def unrelated(s), do: String.replace(s, ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
        @quoted quote do
          String.replace("ab", ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
        end
      end
      """

      expected = """
      defmodule PositionScopedStringReplace do
        @broken Elixir.Regex.replace(~r/(a)(b)/, "ab", fn full, a, b -> full <> a <> b end)
        def unrelated(s), do: String.replace(s, ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)

        @quoted quote do
          String.replace("ab", ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
        end
      end
      """

      confirm_fix(fix(input, @real_message, 2), expected)
    end

    test "uses the absolute Regex name when a local alias shadows Regex" do
      input = """
      defmodule AliasSafeStringReplace do
        alias String, as: Regex
        @broken String.replace("ab", ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
        def broken, do: @broken
      end
      """

      expected = """
      defmodule AliasSafeStringReplace do
        alias String, as: Regex
        @broken Elixir.Regex.replace(~r/(a)(b)/, "ab", fn full, a, b -> full <> a <> b end)
        def broken, do: @broken
      end
      """

      confirm_fix(fix(input, @real_message, 3), expected)
      assert compiles?(fix(input, @real_message, 3))
    end

    test "multi-arity callback over a regex literal" do
      input = """
      defmodule EmailMasker do
        def mask_email(str) do
          String.replace(
            str,
            ~r/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})/,
            fn full, local, domain ->
              masked_local =
                case local do
                  <<first>> <> rest -> <<first>> <> String.duplicate("*", String.length(rest))
                  _ -> "***"
                end

              masked_local <> "@" <> domain
            end
          )
        end
      end
      """

      expected = """
      defmodule EmailMasker do
        def mask_email(str) do
          Elixir.Regex.replace(
            ~r/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})/,
            str,
            fn full, local, domain ->
              masked_local =
                case local do
                  <<first>> <> rest -> <<first>> <> String.duplicate("*", String.length(rest))
                  _ -> "***"
                end

              masked_local <> "@" <> domain
            end
          )
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "guarded multi-arity clause" do
      input = """
      defmodule A do
        def f(s) do
          String.replace(s, ~r/(a)(b)/, fn full, a, b when a != "" -> full <> b end)
        end
      end
      """

      expected = """
      defmodule A do
        def f(s) do
          Elixir.Regex.replace(~r/(a)(b)/, s, fn full, a, b when a != "" -> full <> b end)
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "multi-clause callback" do
      input = """
      defmodule A do
        def f(s) do
          String.replace(s, ~r/(a)(b)/, fn "x", a, b -> a <> b
            full, _a, _b -> full
          end)
        end
      end
      """

      expected = """
      defmodule A do
        def f(s) do
          Elixir.Regex.replace(~r/(a)(b)/, s, fn
            "x", a, b -> a <> b
            full, _a, _b -> full
          end)
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "uppercase ~R sigil" do
      input = """
      defmodule A do
        def f(s), do: String.replace(s, ~R/(a)(b)/, fn full, a, b -> full <> a <> b end)
      end
      """

      expected = """
      defmodule A do
        def f(s), do: Elixir.Regex.replace(~R/(a)(b)/, s, fn full, a, b -> full <> a <> b end)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "fixed output is well-formed (parses)" do
      input = """
      defmodule A do
        def f(s) do
          String.replace(s, ~r/(a)(b)/, fn "x", a, b -> a <> b
            full, _a, _b -> full
          end)
        end
      end
      """

      assert valid_syntax?(fix(input))
    end

    test "leaves neighbouring String.replace calls untouched" do
      input = """
      defmodule A do
        def one(s), do: String.replace(s, "x", "y")

        def two(s), do: String.replace(s, ~r/(a)/, fn full, a -> full <> a end)

        def three(s), do: String.replace(s, ~r/b/, fn m -> m end)
      end
      """

      expected = """
      defmodule A do
        def one(s), do: String.replace(s, "x", "y")

        def two(s), do: Elixir.Regex.replace(~r/(a)/, s, fn full, a -> full <> a end)

        def three(s), do: String.replace(s, ~r/b/, fn m -> m end)
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "the compile-time case the Pattern round cannot reach" do
    @compile_time_input """
    defmodule CompileTimeReplace do
      @masked String.replace("ab", ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
      def masked, do: @masked
    end
    """

    test "rewrites a String.replace evaluated in a module attribute" do
      expected = """
      defmodule CompileTimeReplace do
        @masked Elixir.Regex.replace(~r/(a)(b)/, "ab", fn full, a, b -> full <> a <> b end)
        def masked, do: @masked
      end
      """

      confirm_fix(fix(@compile_time_input), expected)
    end

    test "turns source that does not compile into source that does" do
      refute compiles?(@compile_time_input)
      assert compiles?(fix(@compile_time_input))
    end
  end

  describe "leaves alone what it cannot safely rewrite" do
    test "binary pattern — Regex.replace/3 requires a %Regex{}" do
      input = """
      defmodule A do
        def f(s), do: String.replace(s, "ab", fn full, a -> full <> a end)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "pattern is a variable" do
      input = """
      defmodule A do
        def f(s, re), do: String.replace(s, re, fn full, a -> full <> a end)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "pattern is a module attribute" do
      input = """
      defmodule A do
        @re ~r/(a)/
        def f(s), do: String.replace(s, @re, fn full, a -> full <> a end)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "4-argument form with options" do
      input = """
      defmodule A do
        def f(s), do: String.replace(s, ~r/(a)/, fn full, a -> full <> a end, global: false)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "1-arity callback" do
      input = """
      defmodule A do
        def f(s), do: String.replace(s, ~r/(a)/, fn m -> m end)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "piped form" do
      input = """
      defmodule A do
        def f(s), do: s |> String.replace(~r/(a)/, fn full, a -> full <> a end)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "already using Regex.replace" do
      input = """
      defmodule AlreadyCorrect do
        def mask(str) do
          Regex.replace(~r/(.+)@(.+)/, str, fn _full, local, domain -> local <> "@" <> domain end)
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "no String.replace call at all" do
      input = """
      defmodule Clean do
        def hello, do: :world
      end
      """

      confirm_fix(fix(input), input)
    end

    test "source that does not parse" do
      input = """
      defmodule Broken do
        def f(s), do: String.replace(s, ~r/(a)/, fn full, a ->
      end
      """

      confirm_fix(fix(input), input)
    end
  end

  describe "the rewrite target does what the callback was written for" do
    # Pins the language facts the fix rests on: `String.replace/3` raises on a
    # multi-arity callback, while `Regex.replace/3` — same regex, same callback,
    # arguments swapped — runs it with the full match plus each capture.
    test "String.replace/3 raises where Regex.replace/3 succeeds" do
      callback = fn _full, local, domain -> String.first(local) <> "***@" <> domain end

      # Through `apply/3` so the bad call does not also emit a type warning
      # into this suite's own compile output.
      assert_raise FunctionClauseError, fn ->
        apply(String, :replace, ["alice@example and bob@test", ~r/(\w+)@(\w+)/, callback])
      end

      assert Regex.replace(~r/(\w+)@(\w+)/, "alice@example and bob@test", callback) ==
               "a***@example and b***@test"
    end

    # `Regex.replace/3` tolerates a callback arity that does not line up with the
    # capture count, so the fix cannot turn the crash into a different crash.
    test "Regex.replace/3 tolerates an arity that mismatches the capture count" do
      assert Regex.replace(~r/(a)/, "a", fn full, a, b -> full <> a <> b end) == "aa"
      assert Regex.replace(~r/(a)(b)/, "ab", fn full -> full end) == "ab"
    end
  end
end
