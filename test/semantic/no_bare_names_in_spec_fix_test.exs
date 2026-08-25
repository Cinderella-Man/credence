defmodule Credence.Semantic.NoBareNamesInSpecFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.NoBareNamesInSpec

  @diagnostic %{
    message: "credence_check.ex:2: type sub_list/0 undefined (no such type in Solution)",
    position: 2,
    file: "credence_check.ex",
    severity: :error
  }

  defp fix(source, diagnostic \\ @diagnostic) do
    NoBareNamesInSpec.fix(source, diagnostic)
  end

  test "fixes bare name in spec" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec countsubarray(list, sub_list :: any()) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixed output compiles" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    assert {:ok, []} = RuleHelpers.compile_and_capture(fix(input))
  end

  test "returns source unchanged when no bare name matches" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list :: any()) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "only rewrites the spec on the diagnostic line, never a same-named valid spec elsewhere" do
    # `sub_list` is undefined in module A (the line-2 spec the compiler rejects)
    # but is a *defined* type in module B, where `bar(sub_list)` is a perfectly
    # valid spec meaning "arg of type sub_list". Rewriting B's spec by name would
    # silently widen it to `:: any()`. The fix must touch only line 2.
    input = """
    defmodule A do
      @spec foo(sub_list) :: integer()
      def foo(x), do: x
    end

    defmodule B do
      @type sub_list :: [integer()]
      @spec bar(sub_list) :: integer()
      def bar(x), do: x
    end
    """

    diagnostic = %{
      message: "credence_check.ex:2: type sub_list/0 undefined (no such type in A)",
      position: 2,
      file: "credence_check.ex",
      severity: :error
    }

    expected = """
    defmodule A do
      @spec foo(sub_list :: any()) :: integer()
      def foo(x), do: x
    end

    defmodule B do
      @type sub_list :: [integer()]
      @spec bar(sub_list) :: integer()
      def bar(x), do: x
    end
    """

    confirm_fix(fix(input, diagnostic), expected)
  end

  # ── nested positions (escalation ledger rows 90 and 65) ───────────────────
  #
  # `fix/2` used to rewrite only a bare name sitting as a DIRECT element of the
  # spec's argument list. Every other position returned byte-identical source
  # while `match?/1` still claimed the diagnostic — and `lib/semantic.ex` records
  # `{rule, 1}` even for a no-op and dispatches with `Enum.find`, so the rule
  # consumed the diagnostic, nothing else could claim it, and the compile error
  # survived every pass. Each of these was a reproduced no-op.
  #
  # `compiles?/1` is the assertion that matters here rather than the text: the
  # compiler is a free correctness oracle for a Semantic rule, since the source
  # is already known broken.
  for {label, name, spec, fixed, arity} <- [
        {"a | union", "non_binary", "parse(String.t() | non_binary) :: map",
         "parse(String.t() | (non_binary :: any())) :: map", 1},
        {"a list type", "bare_thing", "parse([bare_thing]) :: map",
         "parse([bare_thing :: any()]) :: map", 1},
        {"the return type", "bare_ret", "parse(binary()) :: bare_ret",
         "parse(binary()) :: bare_ret :: any()", 1},
        {"a tuple type", "bare_tup", "parse({:ok, bare_tup}) :: map",
         "parse({:ok, bare_tup :: any()}) :: map", 1},
        {"a map type", "bare_val", "parse(%{k: bare_val}) :: map",
         "parse(%{k: bare_val :: any()}) :: map", 1},
        {"two levels deep", "deep", "parse([{:ok, deep} | nil]) :: map",
         "parse([{:ok, deep :: any()} | nil]) :: map", 1},
        {"every occurrence, not just the first", "twice", "parse(twice, [twice]) :: map",
         "parse(twice :: any(), [twice :: any()]) :: map", 2}
      ] do
    test "annotates a bare name in #{label}" do
      head =
        if unquote(arity) == 2, do: "def parse(x, y), do: {x, y}", else: "def parse(x), do: x"

      input = """
      defmodule Solution do
        @spec #{unquote(spec)}
        #{head}
      end
      """

      expected = """
      defmodule Solution do
        @spec #{unquote(fixed)}
        #{head}
      end
      """

      assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)

      assert Enum.any?(diagnostics, fn diagnostic ->
               NoBareNamesInSpec.match?(diagnostic) and
                 diagnostic.message ==
                   "credence_check.ex:2: type #{unquote(name)}/0 undefined " <>
                     "(no such type in Solution)"
             end)

      {out, trace} =
        Credence.Semantic.fix_with_trace(input, semantic_rules: [NoBareNamesInSpec])

      refute out == input,
             "no-op: the rule claimed the diagnostic and changed nothing, so the compile " <>
               "error survives every pass while no other rule can claim it"

      confirm_fix(out, expected)
      assert trace == [{NoBareNamesInSpec, 1}]
      assert RuleHelpers.compile_and_capture(out) == RuleHelpers.compile_and_capture(expected)
    end
  end

  test "unwraps a `when` guard — a top-level bare arg was a no-op without it" do
    input = """
    defmodule Solution do
      @spec parse(bare_v, t) :: map when t: atom()
      def parse(x, y), do: {x, y}
    end
    """

    expected = """
    defmodule Solution do
      @spec parse(bare_v :: any(), t) :: map when t: atom()
      def parse(x, y), do: {x, y}
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)

    assert Enum.any?(diagnostics, fn diagnostic ->
             NoBareNamesInSpec.match?(diagnostic) and
               diagnostic.message ==
                 "credence_check.ex:2: type bare_v/0 undefined (no such type in Solution)"
           end)

    {out, trace} =
      Credence.Semantic.fix_with_trace(input, semantic_rules: [NoBareNamesInSpec])

    refute out == input, "a spec carrying a `when` guard was left untouched"
    confirm_fix(out, expected)
    assert trace == [{NoBareNamesInSpec, 1}]
    assert RuleHelpers.compile_and_capture(out) == RuleHelpers.compile_and_capture(expected)
  end

  test "declines a name the `when` guard binds — annotating it does not compile" do
    # `t` is a type VARIABLE bound by the guard, not an undefined type. Annotating
    # it yields `@spec parse(t :: any()) :: map when t: atom()`, which both names
    # the argument `t` and binds `t` — Elixir rejects that outright.
    #
    # This is a regression test for a bug introduced while widening the walk and
    # caught only because the assertion is `compiles?/1` rather than output text:
    # the text looked entirely reasonable.
    input = """
    defmodule Solution do
      @spec parse(t) :: map when t: atom()
      def parse(x), do: x
    end
    """

    diagnostic = %{
      message: "credence_check.ex:2: type t/0 undefined (no such type in Solution)",
      position: 2,
      file: "credence_check.ex",
      severity: :error
    }

    out = fix(input, diagnostic)

    confirm_fix(out, input)
    assert out =~ "when t: atom()", "the guard binding was rewritten"
    assert {:ok, []} = RuleHelpers.compile_and_capture(out)
  end

  test "never rewrites the function-name position, even when it shares the name" do
    # `@spec sub_list(sub_list) :: map` — annotating the head would emit
    # `(sub_list :: any())(sub_list :: any())`, which does not parse as a spec.
    input = """
    defmodule Solution do
      @spec sub_list(sub_list) :: map()
      def sub_list(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @spec sub_list(sub_list :: any()) :: map()
      def sub_list(x), do: x
    end
    """

    out = fix(input)
    confirm_fix(out, expected)
    assert {:ok, []} = RuleHelpers.compile_and_capture(out)
  end

  test "declines a parameterised type — that is not the bare `name/0` reported" do
    # `sub_list(atom())` is `sub_list/1`. The diagnostic named `sub_list/0`, so
    # this occurrence is not the one the compiler rejected and must be left as-is.
    input = """
    defmodule Solution do
      @type sub_list(t) :: [t]
      @spec parse(sub_list(atom())) :: map()
      def parse(x), do: x
    end
    """

    diagnostic = %{
      message: "credence_check.ex:3: type sub_list/0 undefined (no such type in Solution)",
      position: 3,
      file: "credence_check.ex",
      severity: :error
    }

    confirm_fix(fix(input, diagnostic), input)
  end

  test "handles different bare names" do
    diagnostic = %{
      message: "credence_check.ex:2: type my_param/0 undefined (no such type in MyMod)",
      position: 2,
      file: "credence_check.ex",
      severity: :error
    }

    input = """
    defmodule MyMod do
      @spec foo(my_param) :: integer()
      def foo(x), do: x
    end
    """

    expected = """
    defmodule MyMod do
      @spec foo(my_param :: any()) :: integer()
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input, diagnostic), expected)
  end
end
