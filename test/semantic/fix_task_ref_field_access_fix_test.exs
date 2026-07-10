defmodule Credence.Semantic.FixTaskRefFieldAccessFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTaskRefFieldAccess

  # The real diagnostic captured from the pipeline (verbatim).
  @real_msg "you are trying to use/import/require the module RetryDedup.Application which is currently being defined.\n\nThis may happen if you accidentally override the module you want to use. For example:\n\n    defmodule MyApp do\n      defmodule Supervisor do\n        use Supervisor\n      end\n    end\n\nIn the example above, the new Supervisor conflicts with Elixir's Supervisor. This may be fixed by using the fully qualified name in the definition:\n\n    defmodule MyApp.Supervisor do\n      use Supervisor\n    end\n"

  defp fix(source, message \\ @real_msg, line \\ 1) do
    FixTaskRefFieldAccess.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "rewrites Task.ref(task) to task.ref" do
    input = """
    defmodule TaskRefDemo do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = Task.ref(task)
        {task, ref}
      end
    end
    """

    expected = """
    defmodule TaskRefDemo do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = task.ref
        {task, ref}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TaskRefDemo do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = Task.ref(task)
        {task, ref}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "no-op when source has no Task.ref call" do
    input = """
    defmodule CleanModule do
      def hello do
        :world
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
