defmodule Credence.Pattern.NoKernelShadowingCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoKernelShadowing

  describe "flags shadowing variables" do
    test "max in fn parameter" do
      assert [%Issue{rule: :no_kernel_shadowing}] =
               check(NoKernelShadowing, """
               Enum.reduce(list, 0, fn x, max -> max(x, max) end)
               """)
    end

    test "min in match assignment" do
      code = """
      defmodule M do
        def f(list) do
          min = hd(list)
          min
        end
      end
      """

      assert [%Issue{rule: :no_kernel_shadowing}] = check(NoKernelShadowing, code)
    end

    test "max in def parameter" do
      code = """
      defmodule M do
        defp go([], max), do: max
      end
      """

      assert [%Issue{rule: :no_kernel_shadowing}] = check(NoKernelShadowing, code)
    end

    test "max and min together" do
      refute Enum.empty?(
               check(NoKernelShadowing, """
               {max, min} = {100, 0}
               """)
             )
    end

    test "hd in fn parameter" do
      assert [%Issue{rule: :no_kernel_shadowing}] =
               check(NoKernelShadowing, """
               Enum.map(list, fn hd -> hd + 1 end)
               """)
    end

    test "length in match" do
      code =
        """
        defmodule M do
          def f(list) do
            length = Enum.count(list)
            length
          end
        end
        """

      assert [%Issue{rule: :no_kernel_shadowing}] = check(NoKernelShadowing, code)
    end
  end

  describe "does NOT flag" do
    test "Kernel function calls" do
      code = """
      defmodule M do
        def run(a, b), do: max(a, b)
      end
      """

      assert check(NoKernelShadowing, code) == []
    end

    test "idiomatic variable names" do
      assert check(
               NoKernelShadowing,
               """
               Enum.reduce(list, 0, fn x, max_val -> max(x, max_val) end)
               """
             ) == []
    end

    test "atom keys in maps" do
      assert check(NoKernelShadowing, """
             data = %{max: 10, min: 0}
             """) == []
    end

    test "keyword list keys" do
      assert check(NoKernelShadowing, """
             opts = [max: 5, min: 1]
             """) == []
    end
  end
end
