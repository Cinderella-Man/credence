defmodule Credence.Syntax.FixTruncatedModuleReferenceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixTruncatedModuleReference

  defp analyze(code), do: FixTruncatedModuleReference.analyze(code)
  defp fix(code), do: FixTruncatedModuleReference.fix(code)

  describe "fixes truncated __MODULE__ reference" do
    test "in GenServer.start_link call" do
      input = "GenServer.start_link(__MODULE%, %{key: :val}, name: __MODULE__)"

      expected = "GenServer.start_link(__MODULE__, %{key: :val}, name: __MODULE__)"

      confirm_fix(fix(input), expected)
    end

    test "standalone truncated reference" do
      input = "__MODULE%"

      expected = "__MODULE__"

      confirm_fix(fix(input), expected)
    end

    test "in map value" do
      input = "%{key: __MODULE%}"

      expected = "%{key: __MODULE__}"

      confirm_fix(fix(input), expected)
    end

    test "multiple occurrences on different lines" do
      input = """
      x = __MODULE%
      y = __MODULE%
      """

      expected = """
      x = __MODULE__
      y = __MODULE__
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "leaves correct code unchanged" do
    test "proper __MODULE__ reference" do
      code = "GenServer.start_link(__MODULE__, %{key: :val}, name: __MODULE__)"
      confirm_fix(fix(code), code)
    end

    test "plain code without __MODULE" do
      code = "foo(bar)"
      confirm_fix(fix(code), code)
    end

    test "__MODULE__ in module attribute" do
      code = "@module __MODULE__"
      confirm_fix(fix(code), code)
    end
  end

  describe "fixed output no longer flags" do
    test "in GenServer.start_link call" do
      assert analyze(fix("GenServer.start_link(__MODULE%, %{key: :val}, name: __MODULE__)")) == []
    end

    test "standalone" do
      assert analyze(fix("__MODULE%")) == []
    end
  end

  describe "fixed output is well-formed (parses)" do
    test "in GenServer.start_link call" do
      assert valid_syntax?(fix("GenServer.start_link(__MODULE%, %{key: :val}, name: __MODULE__)"))
    end

    test "standalone" do
      assert valid_syntax?(fix("__MODULE%"))
    end
  end
end
