defmodule Credence.Pattern.NoRedundantUnderscoreBindCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantUnderscoreBind

  describe "flags the anti-pattern" do
    test "in function head" do
      assert flagged?(NoRedundantUnderscoreBind, """
             defmodule Example do
               def foo(_ = x), do: x + 1
             end
             """)
    end

    test "in multi-arg function" do
      assert flagged?(NoRedundantUnderscoreBind, """
             defmodule Example do
               def foo(a, _ = b, c), do: a + b + c
             end
             """)
    end

    test "in private function" do
      assert flagged?(NoRedundantUnderscoreBind, """
             defmodule Example do
               defp bar(_ = x), do: x * 2
             end
             """)
    end

    test "in case clause" do
      assert flagged?(NoRedundantUnderscoreBind, """
             case val do
               _ = x -> x + 1
             end
             """)
    end

    test "multiple occurrences" do
      code = """
      defmodule Example do
        def foo(_ = a, _ = b), do: a + b
      end
      """

      assert length(check(NoRedundantUnderscoreBind, code)) == 2
    end
  end

  describe "leaves good code alone" do
    test "simple variable" do
      assert clean?(NoRedundantUnderscoreBind, """
             defmodule Example do
               def foo(x), do: x + 1
             end
             """)
    end

    test "literal pattern" do
      assert clean?(NoRedundantUnderscoreBind, """
             defmodule Example do
               def foo(1), do: :one
             end
             """)
    end

    test "tuple pattern" do
      assert clean?(NoRedundantUnderscoreBind, """
             defmodule Example do
               def foo({a, b}), do: a + b
             end
             """)
    end

    test "underscore without bind" do
      assert clean?(NoRedundantUnderscoreBind, """
             defmodule Example do
               def foo(_), do: :ignored
             end
             """)
    end

    test "regular assignment (not in pattern)" do
      assert clean?(NoRedundantUnderscoreBind, """
             x = 1
             """)
    end
  end
end
