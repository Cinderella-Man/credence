defmodule Credence.Pattern.InconsistentParamNamesFixTest do
  use ExUnit.Case

  alias Credence.Pattern.InconsistentParamNames

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(InconsistentParamNames, code, [])
  end

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    InconsistentParamNames.check(ast, [])
  end

  describe "renames later clauses to match the first" do
    test "two-clause rename in pattern" do
      code = """
      defmodule Bad do
        def process(input, count), do: {input, count}
        def process(data, n), do: {data, n}
      end
      """

      expected = """
      defmodule Bad do
        def process(input, count), do: {input, count}
        def process(input, count), do: {input, count}
      end
      """

      assert fix(code) == expected
    end

    test "renames variables in the body too" do
      code = """
      defmodule Bad do
        def transform(val), do: val + 1
        def transform(x), do: x * 2
      end
      """

      expected = """
      defmodule Bad do
        def transform(val), do: val + 1
        def transform(val), do: val * 2
      end
      """

      assert fix(code) == expected
    end

    test "renames across three clauses" do
      code = """
      defmodule Bad do
        def transform(val, opts), do: {val, opts}
        def transform(value, options), do: {value, options}
        def transform(x, config), do: {x, config}
      end
      """

      expected = """
      defmodule Bad do
        def transform(val, opts), do: {val, opts}
        def transform(val, opts), do: {val, opts}
        def transform(val, opts), do: {val, opts}
      end
      """

      assert fix(code) == expected
    end

    test "renames in guarded clauses (guard and body)" do
      code = """
      defmodule Bad do
        defp loop(num, divisor) when rem(num, divisor) == 0 do
          loop(div(num, divisor), divisor)
        end

        defp loop(n, i) when i * i <= n do
          loop(n, i + 1)
        end
      end
      """

      expected = """
      defmodule Bad do
        defp loop(num, divisor) when rem(num, divisor) == 0 do
          loop(div(num, divisor), divisor)
        end

        defp loop(num, divisor) when divisor * divisor <= num do
          loop(num, divisor + 1)
        end
      end
      """

      assert fix(code) == expected
    end

    test "renames recursive calls in the body" do
      code = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(first, second, third), do: helper(first, second, third)
      end
      """

      expected = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(alpha, beta, gamma), do: helper(alpha, beta, gamma)
      end
      """

      assert fix(code) == expected
    end
  end

  describe "preserves underscore prefix" do
    test "underscore in renamed clause is kept" do
      code = """
      defmodule Bad do
        def process(number, _opts), do: number
        def process(banana, _config), do: banana
      end
      """

      expected = """
      defmodule Bad do
        def process(number, _opts), do: number
        def process(number, _opts), do: number
      end
      """

      assert fix(code) == expected
    end

    test "first clause underscore establishes canonical base" do
      code = """
      defmodule Bad do
        def process(_number, opts), do: opts
        def process(banana, opts), do: {banana, opts}
      end
      """

      expected = """
      defmodule Bad do
        def process(_number, opts), do: opts
        def process(number, opts), do: {number, opts}
      end
      """

      assert fix(code) == expected
    end
  end

  describe "skips non-renamable positions" do
    test "positions with literals or patterns are not renamed" do
      code = """
      defmodule Good do
        def factorial(0, acc), do: acc
        def factorial(n, acc), do: factorial(n - 1, n * acc)
      end
      """

      assert fix(code) == code
    end

    test "bare underscore at a position lets other clauses keep their name there" do
      code = """
      defmodule Fine do
        def handle(_, value), do: value
        def handle(thing, data), do: {thing, data}
      end
      """

      expected = """
      defmodule Fine do
        def handle(_, value), do: value
        def handle(thing, value), do: {thing, value}
      end
      """

      assert fix(code) == expected
    end
  end

  describe "preserves pattern-match equality between arguments" do
    test "leaves a clause whose args share a name untouched" do
      code = """
      defmodule Good do
        def f(x, x), do: x
        def f(a, b), do: {a, b}
      end
      """

      assert fix(code) == code
    end

    test "leaves the original validate_answers_match example unchanged" do
      code = """
      defmodule Good do
        def validate_answers_match(errors, question, answer, answer)
            when is_binary(question) and is_binary(answer), do: errors

        def validate_answers_match(errors, question, answer, confirm)
            when is_binary(question) and is_binary(answer) and is_binary(confirm) do
          [{"confirm_shared_secret_answer", "mismatch"} | errors]
        end

        def validate_answers_match(errors, _question, _answer, _confirm), do: errors
      end
      """

      assert fix(code) == code
    end

    test "does not invent pinning by renaming a free name into a pinned one" do
      code = """
      defmodule Bad do
        def f(answer, confirm), do: {answer, confirm}
        def f(answer, answer), do: answer
      end
      """

      assert fix(code) == code
    end

    test "preserves pinning between top-level arg and nested pattern element" do
      code = """
      defmodule Good do
        def f(x, {x, _meta}), do: x
        def f(alpha, {beta, _meta}), do: {alpha, beta}
      end
      """

      assert fix(code) == code
    end

    test "underscored pinning (_x, _x) is preserved verbatim" do
      code = """
      defmodule Good do
        def f(_x, _x), do: :ok
        def f(a, b), do: {a, b}
      end
      """

      assert fix(code) == code
    end

    test "still renames at non-pinned positions in a function that has pinning elsewhere" do
      code = """
      defmodule Bad do
        def f(x, x, alpha), do: {x, alpha}
        def f(a, b, beta), do: {a, b, beta}
      end
      """

      expected = """
      defmodule Bad do
        def f(x, x, alpha), do: {x, alpha}
        def f(a, b, alpha), do: {a, b, alpha}
      end
      """

      assert fix(code) == expected
    end

    test "still renames around nested pinning" do
      code = """
      defmodule Bad do
        def f(x, {x, _meta}, alpha), do: {x, alpha}
        def f(a, {b, _meta}, beta), do: {a, b, beta}
      end
      """

      expected = """
      defmodule Bad do
        def f(x, {x, _meta}, alpha), do: {x, alpha}
        def f(a, {b, _meta}, alpha), do: {a, b, alpha}
      end
      """

      assert fix(code) == expected
    end

    test "intra-arg duplication leaves position 1 alone, fixes position 2" do
      code = """
      defmodule Bad do
        def f({a, a}, b), do: {a, b}
        def f({x, y}, c), do: {x, y, c}
      end
      """

      expected = """
      defmodule Bad do
        def f({a, a}, b), do: {a, b}
        def f({x, y}, b), do: {x, y, b}
      end
      """

      assert fix(code) == expected
    end
  end

  describe "no-ops" do
    test "consistent names unchanged" do
      code = """
      defmodule Good do
        defp do_fibonacci(prev, _current, 0), do: prev
        defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)
      end
      """

      assert fix(code) == code
    end

    test "single-clause function unchanged" do
      code = """
      defmodule Good do
        defp helper(data, count), do: {data, count}
      end
      """

      assert fix(code) == code
    end

    test "separate functions in same module unchanged" do
      code = """
      defmodule Good do
        def process(data), do: data
        def transform(input), do: input
      end
      """

      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues (basic)" do
      code = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(first, second, third), do: {first, second, third}
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code produces zero issues (fibonacci)" do
      code = """
      defmodule Bad do
        defp do_fibonacci(current, _next, 0), do: current
        defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code produces zero issues (original validate_answers_match bug)" do
      code = """
      defmodule Good do
        def validate_answers_match(errors, question, answer, answer)
            when is_binary(question) and is_binary(answer), do: errors

        def validate_answers_match(errors, question, answer, confirm)
            when is_binary(question) and is_binary(answer) and is_binary(confirm) do
          [{"confirm_shared_secret_answer", "mismatch"} | errors]
        end

        def validate_answers_match(errors, _question, _answer, _confirm), do: errors
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir (guarded mixed clauses)" do
      code = """
      defmodule Bad do
        defp do_largest_cont_sum(list, current, best) when is_list(list) do
          {list, current, best}
        end

        defp do_largest_cont_sum(nums, curr_sum, max_sum) do
          {nums, curr_sum, max_sum}
        end
      end
      """

      assert {:ok, _} = Sourceror.parse_string(fix(code))
    end

    test "fixed code is valid Elixir (pinned tuple + scalar args)" do
      code = """
      defmodule Good do
        def f({a, a}, x, x), do: {a, x}
        def f({b, c}, y, z), do: {b, c, y, z}
      end
      """

      assert {:ok, _} = Sourceror.parse_string(fix(code))
    end
  end
end
