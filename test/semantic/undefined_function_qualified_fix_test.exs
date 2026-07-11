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

  # ── macro capture → lambda wrapper ────────────────────────────

  describe "Integer.is_even/1 → &(Integer.is_even(&1))" do
    test "function capture in Enum.split_with" do
      confirm_fix(
        fix(
          "{evens, odds} = Enum.split_with(list, &Integer.is_even/1)",
          "Integer.is_even/1 is undefined or private"
        ),
        "{evens, odds} = Enum.split_with(list, &(Integer.is_even(&1)))"
      )
    end

    test "realistic module context" do
      input = """
      defmodule Solution do
        def rearrange_even_first(integer_list) do
          {evens, odds} = Enum.split_with(integer_list, &Integer.is_even/1)
          evens ++ odds
        end
      end
      """

      expected = """
      defmodule Solution do
        def rearrange_even_first(integer_list) do
          {evens, odds} = Enum.split_with(integer_list, &(Integer.is_even(&1)))
          evens ++ odds
        end
      end
      """

      confirm_fix(fix(input, "Integer.is_even/1 is undefined or private", 3), expected)
    end

    test "only on reported line" do
      input = """
      a = Enum.filter(list, &Integer.is_odd/1)
      b = Enum.split_with(list, &Integer.is_even/1)
      c = Enum.filter(list, &Integer.is_even/1)
      """

      confirm_fix(fix(input, "Integer.is_even/1 is undefined or private", 2), """
      a = Enum.filter(list, &Integer.is_odd/1)
      b = Enum.split_with(list, &(Integer.is_even(&1)))
      c = Enum.filter(list, &Integer.is_even/1)
      """)
    end
  end

  # ── require module hint ────────────────────────────────────────

  @require_msg "Integer.is_even/1 is undefined or private. There is a macro with the same name and arity. Be sure to require Integer"

  describe "Integer.is_even/1 — Be sure to require Integer → insert require" do
    test "direct call in module" do
      input = """
      defmodule Solution do
        @spec check(integer) :: boolean
        def check(value) do
          Integer.is_even(value)
        end
      end
      """

      expected = """
      defmodule Solution do
        require Integer

        @spec check(integer) :: boolean
        def check(value) do
          Integer.is_even(value)
        end
      end
      """

      confirm_fix(fix(input, @require_msg, 4), expected)
    end

    test "does not duplicate existing require" do
      input = """
      defmodule Solution do
        require Integer

        def check(value) do
          Integer.is_even(value)
        end
      end
      """

      confirm_fix(fix(input, @require_msg, 5), input)
    end

    test "capture form still uses lambda rewrite without require hint" do
      confirm_fix(
        fix(
          "{evens, odds} = Enum.split_with(list, &Integer.is_even/1)",
          "Integer.is_even/1 is undefined or private"
        ),
        "{evens, odds} = Enum.split_with(list, &(Integer.is_even(&1)))"
      )
    end

    test "nested module inserts require in innermost" do
      input = """
      defmodule Outer do
        defmodule Inner do
          def check(value) do
            Integer.is_even(value)
          end
        end
      end
      """

      expected = """
      defmodule Outer do
        defmodule Inner do
          require Integer

          def check(value) do
            Integer.is_even(value)
          end
        end
      end
      """

      confirm_fix(fix(input, @require_msg, 4), expected)
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

  # ── :ets.insert/3 → :ets.insert/2 ─────────────────────────────

  @ets_diag "single quotes around atoms are deprecated. Use double quotes instead"

  describe ":ets.insert/3 → :ets.insert/2 (wrap last two args into tuple)" do
    test "basic 3-arg call" do
      confirm_fix(
        fix(
          ":ets.insert(table, {:key}, :value)",
          @ets_diag
        ),
        ":ets.insert(table, {{:key}, :value})"
      )
    end

    test "in module context" do
      input = """
      defmodule FixEtsInsertThreeArgs do
        def setup do
          table = :ets.new(:my_table, [:set, :public])
          :ets.insert(table, {:key}, :value)
          table
        end
      end
      """

      expected = """
      defmodule FixEtsInsertThreeArgs do
        def setup do
          table = :ets.new(:my_table, [:set, :public])
          :ets.insert(table, {{:key}, :value})
          table
        end
      end
      """

      confirm_fix(fix(input, @ets_diag, 4), expected)
    end

    test "only on reported line" do
      input = """
      :ets.insert(t1, {:a}, 1)
      :ets.insert(t2, {:b}, 2)
      """

      confirm_fix(fix(input, @ets_diag, 1), """
      :ets.insert(t1, {{:a}, 1})
      :ets.insert(t2, {:b}, 2)
      """)
    end

    test "2-arg call is unchanged" do
      source = ":ets.insert(table, {:key, :value})"

      confirm_fix(fix(source, @ets_diag), source)
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

  describe "Enum.flatten → List.flatten" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.flatten(list)",
          "Enum.flatten/1 is undefined or private"
        ),
        "List.flatten(list)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "list |> Enum.flatten()",
          "Enum.flatten/1 is undefined or private"
        ),
        "list |> List.flatten()"
      )
    end

    test "only on reported line" do
      input = """
      Enum.map(list, &f/1)
      Enum.flatten(list)
      Enum.sort(list)
      """

      confirm_fix(
        fix(input, "Enum.flatten/1 is undefined or private", 2),
        """
        Enum.map(list, &f/1)
        List.flatten(list)
        Enum.sort(list)
        """
      )
    end

    test "in module context" do
      input = """
      defmodule M do
        def flat(list) do
          Enum.flatten(list)
        end
      end
      """

      expected = """
      defmodule M do
        def flat(list) do
          List.flatten(list)
        end
      end
      """

      confirm_fix(fix(input, "Enum.flatten/1 is undefined or private", 3), expected)
    end
  end

  # ── Process.exit → exit (drop module) ──────────────────────────

  describe "Process.exit → exit" do
    test "direct call" do
      confirm_fix(
        fix(
          "Process.exit(:normal)",
          "Process.exit/1 is undefined or private"
        ),
        "exit(:normal)"
      )
    end

    test "in module context" do
      input = """
      defmodule M do
        def f do
          Process.exit(:normal)
        end
      end
      """

      expected = """
      defmodule M do
        def f do
          exit(:normal)
        end
      end
      """

      confirm_fix(fix(input, "Process.exit/1 is undefined or private", 3), expected)
    end

    test "only on reported line" do
      input = """
      Process.exit(:normal)
      Process.exit(:shutdown)
      """

      confirm_fix(fix(input, "Process.exit/1 is undefined or private", 1), """
      exit(:normal)
      Process.exit(:shutdown)
      """)
    end

    test "with variable argument" do
      confirm_fix(
        fix(
          "Process.exit(reason)",
          "Process.exit/1 is undefined or private"
        ),
        "exit(reason)"
      )
    end

    test "with tuple argument" do
      confirm_fix(
        fix(
          "Process.exit({:shutdown, :normal})",
          "Process.exit/1 is undefined or private"
        ),
        "exit({:shutdown, :normal})"
      )
    end
  end
end
