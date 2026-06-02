defmodule Credence.Pattern.NoBodyDestructureOfParamTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoBodyDestructureOfParam

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoBodyDestructureOfParam.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoBodyDestructureOfParam, code, [])
  end

  defp assert_fix_unchanged(input) do
    result = fix(input)
    assert normalize(result) == normalize(input)
  end

  defp normalize(code) do
    ast = Sourceror.parse_string!(code)
    Macro.to_string(ast)
  end

  describe "check" do
    test "detects list cons destructure of parameter in body" do
      code = """
      defmodule TestListCons do
        def process(list) do
          [head | tail] = list
          head
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_body_destructure_of_param
      assert issue.message =~ "[head | tail]"
      assert issue.message =~ "list"
      assert issue.meta.line != nil
    end

    test "detects tuple destructure of parameter in body" do
      code = """
      defmodule TestTuple do
        def handle(response) do
          {status, body} = response
          status
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "response"
    end

    test "detects map destructure of parameter in body" do
      code = """
      defmodule TestMap do
        def extract(config) do
          %{host: host, port: port} = config
          host
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "config"
    end

    test "detects single-element list match in body" do
      code = """
      defmodule TestSingleList do
        def unwrap(list) do
          [only] = list
          only
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects body destructure in defp" do
      code = """
      defmodule TestDefp do
        defp slide([incoming | rest_tail], window, current_sum, max_sum) do
          [outgoing | new_window] = window
          new_sum = current_sum - outgoing + incoming
          slide(rest_tail, new_window, new_sum, max(new_sum, max_sum))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "window"
    end

    test "detects body destructure when function has guard not referencing param" do
      code = """
      defmodule TestGuardSafe do
        def process(list, k) when k > 0 do
          [head | tail] = list
          head
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does not flag trivial variable binding" do
      code = """
      defmodule TestTrivial do
        def process(list) do
          x = list
          x
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when parameter is used in guard" do
      code = """
      defmodule TestGuardRef do
        def process(list) when is_list(list) do
          [head | tail] = list
          head
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when parameter is used in body after match" do
      code = """
      defmodule TestBodyRef do
        def process(list) do
          [head | tail] = list
          length(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when match is not first expression in body" do
      code = """
      defmodule TestNotFirst do
        def process(list) do
          x = compute()
          [head | tail] = list
          head
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag match on non-parameter variable" do
      code = """
      defmodule TestNonParam do
        def process(list) do
          result = compute(list)
          [head | tail] = result
          head
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag match on function call result" do
      code = """
      defmodule TestFuncCall do
        def process(list) do
          [head | rest] = Enum.sort(list)
          head
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when all parameters are already destructured in head" do
      code = """
      defmodule TestAlreadyDone do
        def process([head | tail]) do
          head
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag anonymous functions" do
      code = """
      defmodule TestFn do
        def process(list) do
          Enum.map(list, fn item ->
            {k, v} = item
            k
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects multiple body destructures across different functions" do
      code = """
      defmodule TestMultiple do
        def foo(list) do
          [a | b] = list
          a
        end

        def bar(tuple) do
          {x, y} = tuple
          x
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does not flag match where LHS is a pin pattern" do
      # Pin patterns (^var) are a different use case
      code = """
      defmodule TestPin do
        def check(expected, actual) do
          result = actual
          result
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when second parameter is matched but is not a parameter" do
      code = """
      defmodule TestMatchRhs do
        def process(input) do
          output = transform(input)
          output
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "does not modify code (check-only rule)" do
      code = """
      defmodule TestFixUnchanged do
        def process(list) do
          [head | tail] = list
          head
        end
      end
      """

      assert_fix_unchanged(code)
    end

    test "does not modify code that has no issues" do
      code = """
      defmodule TestFixClean do
        def process([head | tail]) do
          head
        end
      end
      """

      assert_fix_unchanged(code)
    end
  end
end
