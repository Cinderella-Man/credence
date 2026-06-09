defmodule Credence.Semantic.PreferDefmoduleWrapperFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.PreferDefmoduleWrapper

  defp fix(source, message, line \\ 1) do
    PreferDefmoduleWrapper.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    @moduledoc \"\"\"
    Solves the bike assignment problem for workers on a grid.
    \"\"\"

    @doc \"\"\"
    Assigns bikes to workers based on shortest Manhattan distance.
    \"\"\"
    @spec assign_bikes([[integer]], [[integer]]) :: [integer]
    def assign_bikes(workers, bikes) do
      Enum.map(workers, fn _worker -> 0 end)
    end

    defp helper(x), do: x
    """

    expected = """
    defmodule Solution do
      @moduledoc \"\"\"
      Solves the bike assignment problem for workers on a grid.
      \"\"\"

      @doc \"\"\"
      Assigns bikes to workers based on shortest Manhattan distance.
      \"\"\"
      @spec assign_bikes([[integer]], [[integer]]) :: [integer]
      def assign_bikes(workers, bikes) do
        Enum.map(workers, fn _worker -> 0 end)
      end

      defp helper(x), do: x
    end
    """

    message = "cannot invoke @/1 outside module"
    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message = "cannot invoke @/1 outside module"

    assert valid_syntax?(
             fix(
               """
               @moduledoc \"\"\"
               Solves the bike assignment problem for workers on a grid.
               \"\"\"

               @doc \"\"\"
               Assigns bikes to workers based on shortest Manhattan distance.
               \"\"\"
               @spec assign_bikes([[integer]], [[integer]]) :: [integer]
               def assign_bikes(workers, bikes) do
                 Enum.map(workers, fn _worker -> 0 end)
               end

               defp helper(x), do: x
               """,
               message
             )
           )
  end
end