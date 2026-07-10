defmodule Credence.Syntax.NoDefpQualifiedNameFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoDefpQualifiedName

  defp analyze(code), do: NoDefpQualifiedName.analyze(code)
  defp fix(code), do: NoDefpQualifiedName.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Broken do
      defp Macro.expand({mod, fun, args}, _env) do
        fn -> apply(mod, fun, args) end
      end

      def call_expand(mfa) do
        Macro.expand(mfa, __ENV__)
      end
    end
    """

    expected = """
    defmodule Broken do
      defp macro_expand({mod, fun, args}, _env) do
        fn -> apply(mod, fun, args) end
      end

      def call_expand(mfa) do
        macro_expand(mfa, __ENV__)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule Broken do
             defp Macro.expand({mod, fun, args}, _env) do
               fn -> apply(mod, fun, args) end
             end

             def call_expand(mfa) do
               Macro.expand(mfa, __ENV__)
             end
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule Broken do
             defp Macro.expand({mod, fun, args}, _env) do
               fn -> apply(mod, fun, args) end
             end

             def call_expand(mfa) do
               Macro.expand(mfa, __ENV__)
             end
           end
           """))
  end
end
