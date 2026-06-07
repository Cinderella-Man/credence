defmodule Credence.Pattern.NoAnonFnApplicationInPipeFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoAnonFnApplicationInPipe

  describe "rewrites |> (fn ... end).() to |> then(fn ... end)" do
    test "single application" do
      input = """
      defmodule BadPipe do
        def process(list) do
          list
          |> Enum.scan(1, &*/2)
          |> (fn s -> [1 | s] end).()
        end
      end
      """

      expected = """
      defmodule BadPipe do
        def process(list) do
          list
          |> Enum.scan(1, &*/2)
          |> then(fn s -> [1 | s] end)
        end
      end
      """

      assert fix(NoAnonFnApplicationInPipe, input) == expected
    end

    test "multiple applications in one pipeline" do
      input = """
      defmodule MultipleBad do
        def process(x) do
          x
          |> (fn a -> a + 1 end).()
          |> (fn b -> b * 2 end).()
        end
      end
      """

      expected = """
      defmodule MultipleBad do
        def process(x) do
          x
          |> then(fn a -> a + 1 end)
          |> then(fn b -> b * 2 end)
        end
      end
      """

      assert fix(NoAnonFnApplicationInPipe, input) == expected
    end
  end

  describe "leaves untouched" do
    test "code already using then/2" do
      code = """
      defmodule GoodThen do
        def process(list) do
          list
          |> Enum.sort()
          |> then(fn s -> [1 | s] end)
        end
      end
      """

      assert fix(NoAnonFnApplicationInPipe, code) == code
    end

    test ".(extra) — then/2 cannot carry extra args" do
      code = "x |> (fn a, b -> a + b end).(y)"
      assert fix(NoAnonFnApplicationInPipe, code) == code
    end
  end
end
