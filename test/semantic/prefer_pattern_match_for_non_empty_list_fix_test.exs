defmodule Credence.Semantic.PreferPatternMatchForNonEmptyListFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferPatternMatchForNonEmptyList

  @match_msg "do not use \"length(items) > 0\" to check if a list is not empty since length always traverses the whole list. Prefer to pattern match on a non-empty list, such as [_ | _], or use \"items != []\" as a guard"

  defp fix(source, message \\ @match_msg, line \\ 1) do
    PreferPatternMatchForNonEmptyList.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes length(items) > 0 in case clause" do
    input = """
    defmodule PreferPatternMatchForNonEmptyList do
      def flush(state, key) do
        case Map.get(state.buffers, key, []) do
          [] ->
            {:noreply, state}

          items when length(items) > 0 ->
            {:noreply, do_flush(key, items, state)}
        end
      end

      defp do_flush(key, items, state), do: {key, items, state}
    end
    """

    expected = """
    defmodule PreferPatternMatchForNonEmptyList do
      def flush(state, key) do
        case Map.get(state.buffers, key, []) do
          [] ->
            {:noreply, state}

          [_ | _] = items ->
            {:noreply, do_flush(key, items, state)}
        end
      end

      defp do_flush(key, items, state), do: {key, items, state}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Foo do
      def bar(items) do
        case items do
          items when length(items) > 0 -> :ok
          _ -> :empty
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "does not modify source without length > 0 pattern" do
    input = """
    defmodule Foo do
      def bar(items) do
        case items do
          [] -> :empty
          _ -> :ok
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
