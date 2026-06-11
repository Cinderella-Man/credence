defmodule Credence.Pattern.AvoidRebindingParameterCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidRebindingParameter

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — parameter rebinding in def/defp body
  # ═══════════════════════════════════════════════════════════════════

  describe "flags parameter rebinding" do
    test "simple rebinding in def" do
      assert flagged?(AvoidRebindingParameter, """
             defmodule Example do
               def compute(n, k) do
                 k = min(k, n - k)
                 k + 1
               end
             end
             """)
    end

    test "simple rebinding in defp" do
      assert flagged?(AvoidRebindingParameter, """
             defmodule Example do
               defp helper(x, y) do
                 y = x + y
                 y * 2
               end
             end
             """)
    end

    test "rebinding with different RHS" do
      assert flagged?(AvoidRebindingParameter, """
             defmodule Example do
               def process(list, acc) do
                 acc = Enum.reduce(list, acc, &+/2)
                 acc
               end
             end
             """)
    end

    test "multiple rebinding flags multiple issues" do
      code = """
      defmodule Example do
        def compute(n, k) do
          k = min(k, n - k)
          n = k + 1
          n
        end
      end
      """

      assert length(check(AvoidRebindingParameter, code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when parameters are not rebound" do
    test "parameters used but not rebound" do
      assert clean?(AvoidRebindingParameter, """
             defmodule Example do
               def compute(n, k) do
                 min(k, n - k) + 1
               end
             end
             """)
    end

    test "local variable assignment that is not a parameter" do
      assert clean?(AvoidRebindingParameter, """
             defmodule Example do
               def compute(n, k) do
                 result = min(k, n - k)
                 result + 1
               end
             end
             """)
    end

    test "no parameters at all" do
      assert clean?(AvoidRebindingParameter, """
             defmodule Example do
               def greet do
                 x = 1
                 x + 2
               end
             end
             """)
    end
  end
end
