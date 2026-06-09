defmodule Credence.Syntax.WrapBareModuleAttrsInDefmoduleAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.WrapBareModuleAttrsInDefmodule

  defp analyze(code), do: WrapBareModuleAttrsInDefmodule.analyze(code)

  test "flags bare @doc/@spec with def outside defmodule" do
    assert [%Issue{rule: :wrap_bare_module_attrs_in_defmodule}] =
             analyze("""
             @doc "Checks if a list is a palindrome."
             @spec palindrome_list?(list()) :: boolean()
             def palindrome_list?([]), do: true
             def palindrome_list?([_]), do: true
             def palindrome_list?(list) do
               list == Enum.reverse(list)
             end
             """)
  end

  test "leaves code inside defmodule alone" do
    assert analyze("""
           defmodule Solution do
             @doc "Checks if a list is a palindrome."
             @spec palindrome_list?(list()) :: boolean()
             def palindrome_list?([]), do: true
           end
           """) == []
  end
end