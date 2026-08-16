defmodule Credence.Semantic.UndefinedFunction.QualifiedFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.UndefinedFunction
  alias Qualified

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  # ── renames ────────────────────────────────────────────────────

  describe "Enum.last → List.last" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.last(list)",
          """
          Enum.last/1 is undefined or private
          """
        ),
        "List.last(list)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "list |> Enum.last()",
          """
          Enum.last/0 is undefined or private
          """
        ),
        "list |> List.last()"
      )
    end

    test "only on reported line" do
      input = """
      Enum.at(x, 0)
      Enum.last(x)
      Enum.count(x)
      """

      confirm_fix(
        fix(
          input,
          """
          Enum.last/1 is undefined or private
          """,
          2
        ),
        """
        Enum.at(x, 0)
        List.last(x)
        Enum.count(x)
        """
      )
    end
  end

  describe "List.reverse → Enum.reverse" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.reverse(items)",
          """
          List.reverse/1 is undefined or private
          """
        ),
        "Enum.reverse(items)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> List.reverse()",
          """
          List.reverse/1 is undefined or private
          """
        ),
        "items |> Enum.reverse()"
      )
    end

    test "mid-pipeline" do
      confirm_fix(
        fix(
          "nums |> Enum.sort() |> List.reverse() |> hd()",
          """
          List.reverse/1 is undefined or private
          """
        ),
        "nums |> Enum.sort() |> Enum.reverse() |> hd()"
      )
    end
  end

  describe "Enum.partition → Enum.split_with (deprecated)" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.partition(list, &is_integer/1)",
          """
          Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
          """
        ),
        "Enum.split_with(list, &is_integer/1)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "list |> Enum.partition(fn {_v, i} -> Integer.is_even(i) end)",
          """
          Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
          """
        ),
        "list |> Enum.split_with(fn {_v, i} -> Integer.is_even(i) end)"
      )
    end

    test "only on reported line" do
      input = """
      x = Enum.map(list, &f/1)
      {a, b} = Enum.partition(list, &pred/1)
      """

      confirm_fix(
        fix(
          input,
          """
          Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
          """,
          2
        ),
        """
        x = Enum.map(list, &f/1)
        {a, b} = Enum.split_with(list, &pred/1)
        """
      )
    end
  end

  describe "List.pop → List.last" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.pop(items)",
          """
          List.pop/1 is undefined or private
          """
        ),
        "List.last(items)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> List.pop()",
          """
          List.pop/1 is undefined or private
          """
        ),
        "items |> List.last()"
      )
    end

    test "mid-pipeline" do
      confirm_fix(
        fix(
          "acc |> List.pop() |> elem(0)",
          """
          List.pop/1 is undefined or private
          """
        ),
        "acc |> List.last() |> elem(0)"
      )
    end
  end

  describe "List.drop → Enum.drop" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.drop(items, 3)",
          """
          List.drop/2 is undefined or private
          """
        ),
        "Enum.drop(items, 3)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> List.drop(1)",
          """
          List.drop/2 is undefined or private
          """
        ),
        "items |> Enum.drop(1)"
      )
    end

    test "nested" do
      confirm_fix(
        fix(
          "List.last(sorted) * List.second(List.drop(sorted, n))",
          """
          List.drop/2 is undefined or private
          """
        ),
        "List.last(sorted) * List.second(Enum.drop(sorted, n))"
      )
    end
  end

  describe "Enum.cycle → Stream.cycle" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.cycle(items)",
          """
          Enum.cycle/1 is undefined or private
          """
        ),
        "Stream.cycle(items)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> Enum.cycle()",
          """
          Enum.cycle/1 is undefined or private
          """
        ),
        "items |> Stream.cycle()"
      )
    end

    test "inside expression" do
      confirm_fix(
        fix(
          "Enum.flat_map(1..10, &Enum.cycle([&1]))",
          """
          Enum.cycle/1 is undefined or private
          """
        ),
        "Enum.flat_map(1..10, &Stream.cycle([&1]))"
      )
    end
  end

  # ── literals ───────────────────────────────────────────────────

  describe "Float.NegInfinity → :neg_infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Float.NegInfinity()",
          """
          Float.NegInfinity/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Float.NegInfinity",
          """
          Float.NegInfinity/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "as function argument" do
      confirm_fix(
        fix(
          "validate(root, Float.NegInfinity(), Float.PositiveInfinity())",
          """
          Float.NegInfinity/0 is undefined or private
          """
        ),
        "validate(root, :neg_infinity, Float.PositiveInfinity())"
      )
    end
  end

  describe "Float.PositiveInfinity → :infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Float.PositiveInfinity()",
          """
          Float.PositiveInfinity/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Float.PositiveInfinity",
          """
          Float.PositiveInfinity/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "as function argument" do
      confirm_fix(
        fix(
          "validate(root, :neg_infinity, Float.PositiveInfinity())",
          """
          Float.PositiveInfinity/0 is undefined or private
          """
        ),
        "validate(root, :neg_infinity, :infinity)"
      )
    end
  end

  describe "Float.NegInf → :neg_infinity" do
    test "direct call" do
      confirm_fix(
        fix(
          "Float.NegInf()",
          """
          Float.NegInf/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end
  end

  describe "Float.Infinity → :infinity" do
    test "direct call" do
      confirm_fix(
        fix(
          "Float.Infinity()",
          """
          Float.Infinity/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end
  end

  describe "Float.inf → :infinity / -Float.inf → :neg_infinity" do
    test "negated without parens" do
      confirm_fix(
        fix(
          "max_num = -Float.inf",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "max_num = :neg_infinity"
      )
    end

    test "negated with parens" do
      confirm_fix(
        fix(
          "max_num = -Float.inf()",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "max_num = :neg_infinity"
      )
    end

    test "positive without parens" do
      confirm_fix(
        fix(
          "upper = Float.inf",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "upper = :infinity"
      )
    end

    test "positive with parens" do
      confirm_fix(
        fix(
          "upper = Float.inf()",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "upper = :infinity"
      )
    end

    test "realistic context" do
      code = """
          max_num = -Float.inf
          second_max_num = -Float.inf
      """

      confirm_fix(
        fix(
          code,
          """
          Float.inf/0 is undefined or private
          """,
          1
        ),
        """
            max_num = :neg_infinity
            second_max_num = -Float.inf
        """
      )
    end
  end

  describe "Integer.min_value → :neg_infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Integer.min_value()",
          """
          Integer.min_value/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Integer.min_value",
          """
          Integer.min_value/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "in module attribute" do
      confirm_fix(
        fix(
          "@min_bound Integer.min_value()",
          """
          Integer.min_value/0 is undefined or private
          """
        ),
        "@min_bound :neg_infinity"
      )
    end
  end

  describe "Integer.max_value → :infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Integer.max_value()",
          """
          Integer.max_value/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Integer.max_value",
          """
          Integer.max_value/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "in module attribute" do
      confirm_fix(
        fix(
          "@max_bound Integer.max_value()",
          """
          Integer.max_value/0 is undefined or private
          """
        ),
        "@max_bound :infinity"
      )
    end
  end

  describe "List.at → Enum.at" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.at(list, index)",
          """
          List.at/2 is undefined or private
          """
        ),
        "Enum.at(list, index)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "list |> List.at(index)",
          """
          List.at/2 is undefined or private
          """
        ),
        "list |> Enum.at(index)"
      )
    end

    test "only on reported line" do
      input = """
      List.first(xs)
      List.at(xs, 0)
      List.last(xs)
      """

      confirm_fix(
        fix(
          input,
          """
          List.at/2 is undefined or private
          """,
          2
        ),
        """
        List.first(xs)
        Enum.at(xs, 0)
        List.last(xs)
        """
      )
    end

    test "realistic context with div" do
      input = """
      defmodule Solution do
        def get_middle(list) do
          index = div(length(list), 2)
          List.at(list, index)
        end
      end
      """

      expected = """
      defmodule Solution do
        def get_middle(list) do
          index = div(length(list), 2)
          Enum.at(list, index)
        end
      end
      """

      confirm_fix(fix(input, "List.at/2 is undefined or private", 4), expected)
    end
  end

  describe "Enum.length → length" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.length(list)",
          """
          Enum.length/1 is undefined or private
          """
        ),
        "length(list)"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "n = Enum.length(items)",
          """
          Enum.length/1 is undefined or private
          """
        ),
        "n = length(items)"
      )
    end

    test "only on reported line" do
      input = """
      Enum.count(x)
      Enum.length(x)
      Enum.at(x, 0)
      """

      confirm_fix(
        fix(
          input,
          """
          Enum.length/1 is undefined or private
          """,
          2
        ),
        """
        Enum.count(x)
        length(x)
        Enum.at(x, 0)
        """
      )
    end

    test "realistic context from LLM log" do
      input = """
      defmodule Solution do
        @spec partition_array(list(integer()), integer()) :: integer()
        def partition_array(list, k) when is_list(list) and is_integer(k) do
          {less, _greater_equal} = Enum.split_with(list, fn element -> element < k end)
          Enum.length(less)
        end
      end
      """

      expected = """
      defmodule Solution do
        @spec partition_array(list(integer()), integer()) :: integer()
        def partition_array(list, k) when is_list(list) and is_integer(k) do
          {less, _greater_equal} = Enum.split_with(list, fn element -> element < k end)
          length(less)
        end
      end
      """

      confirm_fix(fix(input, "Enum.length/1 is undefined or private", 5), expected)
    end
  end

  # ── List.* → Enum.* ─────────────────────────────────────────────

  describe "List.max → Enum.max" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.max(integers)",
          "List.max/1 is undefined or private"
        ),
        "Enum.max(integers)"
      )
    end

    test "in expression" do
      confirm_fix(
        fix(
          "List.max(integers) - List.min(integers)",
          "List.max/1 is undefined or private"
        ),
        "Enum.max(integers) - List.min(integers)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "integers |> List.max()",
          "List.max/1 is undefined or private"
        ),
        "integers |> Enum.max()"
      )
    end
  end

  describe "List.min → Enum.min" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.min(integers)",
          "List.min/1 is undefined or private"
        ),
        "Enum.min(integers)"
      )
    end

    test "in expression" do
      confirm_fix(
        fix(
          "List.max(integers) - List.min(integers)",
          "List.min/1 is undefined or private"
        ),
        "List.max(integers) - Enum.min(integers)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "integers |> List.min()",
          "List.min/1 is undefined or private"
        ),
        "integers |> Enum.min()"
      )
    end
  end

  describe "List.sum → Enum.sum" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.sum(numbers)",
          "List.sum/1 is undefined or private"
        ),
        "Enum.sum(numbers)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "numbers |> List.sum()",
          "List.sum/1 is undefined or private"
        ),
        "numbers |> Enum.sum()"
      )
    end
  end

  describe "List.product → Enum.product" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.product(numbers)",
          "List.product/1 is undefined or private"
        ),
        "Enum.product(numbers)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "numbers |> List.product()",
          "List.product/1 is undefined or private"
        ),
        "numbers |> Enum.product()"
      )
    end
  end

  describe "Enum.sum/2 → Enum.sum_by/2 (repair — sum with a mapper)" do
    test "direct call with anonymous fn" do
      confirm_fix(
        fix(
          "Enum.sum(1..n, fn k -> 1.0 / k end)",
          "Enum.sum/2 is undefined or private. Did you mean:\n\n    * sum/1\n"
        ),
        "Enum.sum_by(1..n, fn k -> 1.0 / k end)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "1..n |> Enum.sum(fn k -> 1.0 / k end)",
          "Enum.sum/2 is undefined or private"
        ),
        "1..n |> Enum.sum_by(fn k -> 1.0 / k end)"
      )
    end

    test "valid Enum.sum/1 is untouched (no diagnostic, different arity)" do
      confirm_fix(
        fix("Enum.sum(numbers)", "Enum.last/1 is undefined or private"),
        "Enum.sum(numbers)"
      )
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "qualified: no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"

      confirm_fix(
        fix(source, """
        MyModule.foo/1 is undefined or private
        """),
        source
      )
    end

    test "unknown Float function unchanged" do
      source = "Float.unknown_thing()"

      confirm_fix(
        fix(source, """
        Float.unknown_thing/0 is undefined or private
        """),
        source
      )
    end
  end

  # Folded from standalone candidate rules (prefer_enum_join,
  # prefer_enum_slice_over_list_slice, prefer_map_size_kernel,
  # prefer_tl_over_enum_tail) — each was a duplicate of this diagnostic matcher.

  describe "String.join → Enum.join" do
    test "direct call" do
      confirm_fix(
        fix(~S'String.join(parts, ", ")', "String.join/2 is undefined or private"),
        ~S'Enum.join(parts, ", ")'
      )
    end
  end

  describe "List.slice → Enum.slice" do
    test "direct call" do
      confirm_fix(
        fix("List.slice(list, 1, 3)", "List.slice/3 is undefined or private"),
        "Enum.slice(list, 1, 3)"
      )
    end
  end

  describe "Map.size → map_size (deprecated)" do
    test "direct call" do
      confirm_fix(
        fix("Map.size(map)", "Map.size/1 is deprecated. Use map_size/1 instead."),
        "map_size(map)"
      )
    end
  end

  describe "Enum.tail → tl" do
    test "direct call" do
      confirm_fix(
        fix("Enum.tail(chars)", "Enum.tail/1 is undefined or private"),
        "tl(chars)"
      )
    end
  end

  # ── Erlang modules ─────────────────────────────────────────────
  #
  # The compiler writes these with the leading colon (`:math.round/1 is
  # undefined or private`), which `\w` cannot match — so the module capture
  # used to come back as `"math"` and a `{:drop_module, "round"}` keyed on it
  # emitted `:round(x)`, which does not parse.

  describe "Erlang module keys keep their leading colon" do
    test ":crypto.hex → Base.encode16" do
      confirm_fix(
        fix(":crypto.hex(data)", ":crypto.hex/1 is undefined or private"),
        "Base.encode16(data)"
      )
    end

    test ":erlang.warn → IO.warn" do
      confirm_fix(
        fix(":erlang.warn(msg)", ":erlang.warn/1 is undefined or private"),
        "IO.warn(msg)"
      )
    end

    test ":queue.empty → :queue.new" do
      confirm_fix(
        fix(":queue.empty()", ":queue.empty/0 is undefined or private"),
        ":queue.new()"
      )
    end

    test ":math.min → Kernel.min" do
      confirm_fix(
        fix(":math.min(a, b)", ":math.min/2 is undefined or private"),
        "Kernel.min(a, b)"
      )
    end

    test ":math.max → Kernel.max" do
      confirm_fix(
        fix(":math.max(a, b)", ":math.max/2 is undefined or private"),
        "Kernel.max(a, b)"
      )
    end

    test ":math.round drops the module" do
      confirm_fix(
        fix(":math.round(x)", ":math.round/1 is undefined or private"),
        "round(x)"
      )
    end
  end

  # ── alias boundaries ───────────────────────────────────────────
  #
  # A diagnostic names only the LAST segment of an alias, so a user's own
  # `MyApp.Input.List.reverse/1` is indistinguishable from stdlib
  # `List.reverse/1` in the message. Rewriting the first as if it were the
  # second invents a module that does not exist.

  describe "nested aliases are left alone" do
    test "does not rewrite a user's own nested module" do
      source = "Input.List.reverse(l)"
      confirm_fix(fix(source, "MyApp.Input.List.reverse/1 is undefined or private"), source)
    end

    test "does not rewrite a fully-qualified user module" do
      source = "MyApp.Input.List.reverse(l)"
      confirm_fix(fix(source, "MyApp.Input.List.reverse/1 is undefined or private"), source)
    end

    test "does not rewrite a module whose name merely ends with a table key" do
      source = "MyList.reverse(l)"
      confirm_fix(fix(source, "MyList.reverse/1 is undefined or private"), source)
    end

    test "still rewrites the unqualified stdlib call" do
      confirm_fix(
        fix("List.reverse(l)", "List.reverse/1 is undefined or private"),
        "Enum.reverse(l)"
      )
    end
  end

  # ── Call-boundary anchoring (docs/16 4.6d) ──────────────────────────
  #
  # These replacements were plain substring searches, and a function name is a
  # prefix of longer real names. `Base.hex_encode` is a prefix of
  # `Base.hex_encode32` — which the compiler lists in that very diagnostic's
  # did-you-mean block — so repairing one broken call produced two. docs/16
  # deferred the Agent / NaiveDateTime / List.keystore / exit rows on this
  # anchoring rather than on anything about the rows.

  describe "a replacement stops at the call boundary" do
    # NON-VACUOUS by construction, and it took two attempts to get there.
    # `List.pop` IS a table row (-> `List.last`) and `List.pop_at/2` is a REAL
    # function, so both sit on one line and only the broken one may be rewritten.
    #
    # Attempt 1 used `Base.hex_encode`, which has no table row — the fix was a
    # no-op with or without the anchor, so the test passed while proving
    # nothing. Attempt 2 put the broken call FIRST, and the replacement is
    # `global: false`: it matched the right call before ever reaching the longer
    # one, so it passed too. The longer name has to come first for the anchor to
    # be what decides. Reverting the anchor reddens this.
    test "the broken call is repaired and a longer real call beside it is not" do
      source = """
      defmodule AnchorPrefix do
        def f(a, b), do: {List.pop_at(b, 0), List.pop(a)}
      end
      """

      expected = """
      defmodule AnchorPrefix do
        def f(a, b), do: {List.pop_at(b, 0), List.last(a)}
      end
      """

      diagnostic = %{
        severity: :error,
        message: "List.pop/1 is undefined or private",
        position: {2, 1}
      }

      confirm_fix(UndefinedFunction.fix(source, diagnostic), expected)
    end

    test "a line holding ONLY the longer real call is untouched" do
      source = """
      defmodule AnchorLongerOnly do
        def f(b), do: List.pop_at(b, 0)
      end
      """

      diagnostic = %{
        severity: :error,
        message: "List.pop/1 is undefined or private",
        position: {2, 1}
      }

      confirm_fix(UndefinedFunction.fix(source, diagnostic), source)
    end
  end

  # ── Base.hex_encode / hex_encode64 (docs/16 4.6d, ledger row 119) ──────
  #
  # Deferred on call-boundary anchoring, not on themselves: `hex_encode` is a
  # prefix of the REAL `hex_encode32`, which the compiler lists in this
  # diagnostic's own did-you-mean block, so before the anchor one broken call
  # became two. Verified against the actual `Base` module — only `hex_encode32`
  # and `hex_decode32` exist; `hex_encode` and `hex_encode64` are both invented.

  describe "Base.hex_encode" do
    defp base_fix(source, message) do
      UndefinedFunction.fix(source, %{severity: :error, message: message, position: {2, 1}})
    end

    test "hex_encode/1 becomes encode16 with case: :lower" do
      confirm_fix(
        base_fix(
          """
          defmodule HexOne do
            def f(x), do: Base.hex_encode(x)
          end
          """,
          "Base.hex_encode/1 is undefined or private"
        ),
        """
        defmodule HexOne do
          def f(x), do: Base.encode16(x, case: :lower)
        end
        """
      )
    end

    # `Base.encode16` defaults to UPPERCASE and an LLM reaching for `hex_encode`
    # is translating Python's `bytes.hex()`, which is lowercase — so the option
    # is the repair, not decoration. Two-argument callers keep their own.
    test "hex_encode/2 keeps the caller's options" do
      confirm_fix(
        base_fix(
          """
          defmodule HexTwo do
            def f(x), do: Base.hex_encode(x, case: :upper)
          end
          """,
          "Base.hex_encode/2 is undefined or private"
        ),
        """
        defmodule HexTwo do
          def f(x), do: Base.encode16(x, case: :upper)
        end
        """
      )
    end

    test "hex_encode64/1 becomes encode64 — base64 has no hex variant" do
      confirm_fix(
        base_fix(
          """
          defmodule HexB64 do
            def f(x), do: Base.hex_encode64(x)
          end
          """,
          "Base.hex_encode64/1 is undefined or private"
        ),
        """
        defmodule HexB64 do
          def f(x), do: Base.encode64(x)
        end
        """
      )
    end

    # The trap this row was deferred for. `hex_encode32/1` is REAL; a
    # `hex_encode/1` diagnostic must not touch it.
    test "CONTROL: the real hex_encode32 is left alone" do
      source = """
      defmodule HexReal do
        def f(x), do: Base.hex_encode32(x)
      end
      """

      assert base_fix(source, "Base.hex_encode/1 is undefined or private") == source
    end
  end

  # ── List.keystore/3 -> /4 (docs/16 4.6d) ────────────────────────────
  #
  # The last of the deferred rows, and the one that needed a new table verb.
  # LLMs confuse `List.keystore/4` with `List.keyfind/3` and leave out the
  # POSITION argument, which belongs SECOND — so appending (the only thing
  # `:rename_add_arg` can do) would produce a call that compiles and means
  # something else. `:insert_arg` puts it at an index.

  describe "List.keystore/3" do
    defp keystore(source) do
      UndefinedFunction.fix(source, %{
        severity: :error,
        message: "List.keystore/3 is undefined or private. Did you mean: * keystore/4",
        position: {2, 1}
      })
    end

    test "inserts the position argument second" do
      confirm_fix(
        keystore("""
        defmodule KsPlain do
          def f(l, k, t), do: List.keystore(l, k, t)
        end
        """),
        """
        defmodule KsPlain do
          def f(l, k, t), do: List.keystore(l, 0, k, t)
        end
        """
      )
    end

    # Arguments are split on top-level commas of the SHADOW, so a comma inside a
    # string or a nested bracket is not a separator. Getting this wrong would
    # insert the position into the middle of someone's tuple.
    test "commas inside a string and a nested bracket are not separators" do
      confirm_fix(
        keystore("""
        defmodule KsNested do
          def f(l), do: List.keystore(l, "a, b", {:x, [1, 2]})
        end
        """),
        """
        defmodule KsNested do
          def f(l), do: List.keystore(l, 0, "a, b", {:x, [1, 2]})
        end
        """
      )
    end

    # The control, and it was a real bug before the guard existed: a CORRECT
    # `List.keystore/4` on the line is not what the /3 diagnostic is about, and
    # inserting into it produced `List.keystore(l, 0, 0, :k, {:k, 1})`.
    test "CONTROL: an already-correct keystore/4 call is left alone" do
      source = """
      defmodule KsCorrect do
        def f(l), do: List.keystore(l, 0, :k, {:k, 1})
      end
      """

      assert keystore(source) == source
    end
  end
end
