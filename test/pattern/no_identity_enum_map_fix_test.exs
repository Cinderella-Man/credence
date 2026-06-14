defmodule Credence.Pattern.NoIdentityEnumMapFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIdentityEnumMap

  describe "fix/2 — direct calls" do
    test "fixes Enum.map(list, fn x -> x end) → Enum.to_list(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.map(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.to_list(list)
      end
      """

      confirm_fix(fix(NoIdentityEnumMap, input), expected)
    end

    test "fixes Enum.map(enum, &Function.identity/1) → Enum.to_list(enum)" do
      input = """
      defmodule Example do
        def run(enum), do: Enum.map(enum, &Function.identity/1)
      end
      """

      expected = """
      defmodule Example do
        def run(enum), do: Enum.to_list(enum)
      end
      """

      confirm_fix(fix(NoIdentityEnumMap, input), expected)
    end

    test "preserves a compound argument expression" do
      input = """
      defmodule Example do
        def run(a, b), do: Enum.map(a ++ b, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(a, b), do: Enum.to_list(a ++ b)
      end
      """

      confirm_fix(fix(NoIdentityEnumMap, input), expected)
    end
  end

  describe "fix/2 — piped form" do
    test "fixes list |> Enum.map(& &1) → list |> Enum.to_list()" do
      input = """
      defmodule Example do
        def run(list), do: list |> Enum.map(& &1)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: list |> Enum.to_list()
      end
      """

      confirm_fix(fix(NoIdentityEnumMap, input), expected)
    end
  end

  describe "fix/2 — leaves non-identity maps untouched" do
    test "does not rewrite a real transform" do
      input = """
      defmodule Example do
        def run(list), do: Enum.map(list, fn x -> x + 1 end)
      end
      """

      confirm_fix(fix(NoIdentityEnumMap, input), input)
    end
  end
end
