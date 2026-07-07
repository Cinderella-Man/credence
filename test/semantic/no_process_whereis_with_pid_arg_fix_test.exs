defmodule Credence.Semantic.NoProcessWhereisWithPidArgFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoProcessWhereisWithPidArg

  @real_message "credence_check.ex: cannot compile module EventBus (errors have been logged)"

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoProcessWhereisWithPidArg.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes case Process.whereis guard around Process.demonitor" do
    input = """
    defmodule Example do
      def demo do
        refs = :erlang.make_ref() |> List.wrap()

        Enum.each(refs, fn ref ->
          case Process.whereis(self()) do
            nil -> :ok
            _ -> Process.demonitor(ref)
          end
        end)
      end
    end
    """

    expected = """
    defmodule Example do
      def demo do
        refs = :erlang.make_ref() |> List.wrap()

        Enum.each(refs, fn ref ->
          Process.demonitor(ref)
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def demo do
        refs = :erlang.make_ref() |> List.wrap()

        Enum.each(refs, fn ref ->
          case Process.whereis(self()) do
            nil -> :ok
            _ -> Process.demonitor(ref)
          end
        end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no Process.whereis pattern" do
    input = """
    defmodule CleanExample do
      def demo do
        Process.demonitor(make_ref())
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end
end
