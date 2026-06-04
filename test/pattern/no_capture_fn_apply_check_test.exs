defmodule Credence.Pattern.NoCaptureFnApplyCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoCaptureFnApply

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaptureFnApply.check(ast, [])
  end

  describe "no issue" do
    test "passes normal function calls" do
      code = """
      defmodule Good do
        def process(el, col) do
          Enum.at(el, col)
        end
      end
      """

      assert check(code) == []
    end

    test "passes anonymous function application" do
      code = """
      defmodule Good do
        def process(x) do
          fun = fn y -> y * 2 end
          fun.(x)
        end
      end
      """

      assert check(code) == []
    end

    test "passes function reference capture applied (no &N placeholders)" do
      code = """
      defmodule Good do
        def process(list) do
          (&Enum.map/2).(list, &(&1 + 1))
        end
      end
      """

      assert check(code) == []
    end

    # The cases below COULD be inlined textually, but the rewrite would change the
    # answer, so the narrowed rule deliberately leaves them alone.

    test "skips arg with side effects duplicated by a repeated placeholder" do
      # Inlining (& &1 + &1).(f()) -> f() + f() would call f/0 twice instead of once.
      code = """
      defmodule Skip do
        def run do
          (& &1 + &1).(f())
        end
      end
      """

      assert check(code) == []
    end

    test "skips a dropped (unreferenced) side-effecting arg" do
      # Inlining (& &2).(side(), other()) -> other() would drop the side()/0 call.
      code = """
      defmodule Skip do
        def run do
          (& &2).(side(), other())
        end
      end
      """

      assert check(code) == []
    end

    test "skips out-of-order placeholders with side-effecting args" do
      # Inlining (& &2 + &1).(p(), q()) -> q() + p() would evaluate them in the wrong order.
      code = """
      defmodule Skip do
        def run do
          (& &2 + &1).(p(), q())
        end
      end
      """

      assert check(code) == []
    end

    test "skips a single call-valued arg" do
      code = """
      defmodule Skip do
        def run do
          (& &1 + 1).(g.())
        end
      end
      """

      assert check(code) == []
    end

    test "skips a non-scalar (tuple) literal arg" do
      code = """
      defmodule Skip do
        def run do
          (& elem(&1, 0)).({a, b})
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "flags (safe to inline: pure variable/literal args)" do
    test "detects capture with &1 placeholder applied to a variable" do
      code = """
      defmodule Bad do
        def column_sum(matrix, col) do
          Enum.reduce(matrix, 0, fn el, acc -> acc + (&Enum.at(&1, col)).(el) end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_capture_fn_apply
      assert issue.message =~ "Inline the arguments"
      assert issue.meta.line != nil
    end

    test "detects capture with &1 in arithmetic" do
      code = """
      defmodule Bad do
        def double(x) do
          (& &1 * 2).(x)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects a duplicated placeholder when the arg is a pure variable" do
      code = """
      defmodule Bad do
        def run(el) do
          (& &1 + &1).(el)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects out-of-order placeholders when the args are pure variables" do
      code = """
      defmodule Bad do
        def run(a, b) do
          (& &2 + &1).(a, b)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects multiple capture applications" do
      code = """
      defmodule Bad do
        def process(a, b) do
          x = (& &1 + 1).(a)
          y = (& &1 * 2).(b)
          x + y
        end
      end
      """

      assert length(check(code)) == 2
    end
  end
end
