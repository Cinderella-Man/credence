defmodule Credence.Semantic.UndefinedLocalFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedLocalFunction

  defp error(msg), do: %{severity: :error, message: msg, position: {1, 1}}

  describe "match?/1 – matches known replacements" do
    test "infinity/0" do
      assert UndefinedLocalFunction.match?(
               error("undefined function infinity/0 (expected MyModule to define such a function or for it to be imported, but none are available)")
             )
    end
  end

  describe "match?/1 – rejects" do
    test "unknown local function" do
      refute UndefinedLocalFunction.match?(
               error("undefined function foobar/0 (expected MyModule to define such a function or for it to be imported, but none are available)")
             )
    end

    test "module-qualified undefined (handled by UndefinedFunction)" do
      refute UndefinedLocalFunction.match?(
               error("Enum.last/1 is undefined or private")
             )
    end

    test "warning severity" do
      refute UndefinedLocalFunction.match?(%{
               severity: :warning,
               message: "undefined function infinity/0 (expected MyModule to define such a function)",
               position: {1, 1}
             })
    end

    test "unrelated error" do
      refute UndefinedLocalFunction.match?(error("some other error"))
    end
  end

  describe "to_issue/1" do
    test "extracts rule and line" do
      issue =
        UndefinedLocalFunction.to_issue(%{
          severity: :error,
          message: "undefined function infinity/0 (expected MyModule to define such a function)",
          position: {19, 76}
        })

      assert issue.rule == :undefined_local_function
      assert issue.meta.line == 19
    end
  end
end
