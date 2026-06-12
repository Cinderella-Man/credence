defmodule Credence.Pattern.NoIdentityEnumMapCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIdentityEnumMap

  describe "check/2 — flags Enum.map with an identity callback" do
    test "flags Enum.map(list, fn x -> x end)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.map(list, fn x -> x end)
      end
      """

      [issue] = check(NoIdentityEnumMap, code)
      assert issue.rule == :no_identity_enum_map
      assert issue.message =~ "Enum.to_list"
    end

    test "flags the piped form list |> Enum.map(& &1)" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.map(& &1)
      end
      """

      assert [_issue] = check(NoIdentityEnumMap, code)
    end

    test "flags Enum.map(enum, &Function.identity/1)" do
      code = """
      defmodule Example do
        def run(enum), do: Enum.map(enum, &Function.identity/1)
      end
      """

      assert [_issue] = check(NoIdentityEnumMap, code)
    end
  end

  describe "check/2 — leaves non-identity maps alone" do
    test "ignores a real transform" do
      code = """
      defmodule Example do
        def run(list), do: Enum.map(list, fn x -> x + 1 end)
      end
      """

      assert clean?(NoIdentityEnumMap, code)
    end

    test "ignores &(&1 + 1)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.map(list, &(&1 + 1))
      end
      """

      assert clean?(NoIdentityEnumMap, code)
    end

    test "ignores a map callback that is not identity" do
      code = """
      defmodule Example do
        def run(list), do: Enum.map(list, fn x -> {x, x} end)
      end
      """

      assert clean?(NoIdentityEnumMap, code)
    end
  end
end
