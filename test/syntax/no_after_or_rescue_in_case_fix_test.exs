defmodule Credence.Syntax.NoAfterOrRescueInCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoAfterOrRescueInCase

  defp analyze(code), do: NoAfterOrRescueInCase.analyze(code)
  defp fix(code), do: NoAfterOrRescueInCase.fix(code)

  test "fixes case with after and rescue" do
    input = """
    defmodule TestModule do
      def run do
        case Map.get(%{}, :key) do
          nil ->
            :not_found

          value ->
            {:ok, value}

          # trailing comment
        after
          :cleanup
        rescue
          _ -> :error
        end
      end
    end
    """

    expected = """
    defmodule TestModule do
      def run do
        try do
          case Map.get(%{}, :key) do
            nil ->
              :not_found

            value ->
              {:ok, value}

            # trailing comment
          end
        after
          :cleanup
        rescue
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes case with only after" do
    input = """
    defmodule TestModule do
      def run do
        case Map.get(%{}, :key) do
          nil -> :not_found
          value -> {:ok, value}
        after
          :cleanup
        end
      end
    end
    """

    expected = """
    defmodule TestModule do
      def run do
        try do
          case Map.get(%{}, :key) do
            nil -> :not_found
            value -> {:ok, value}
          end
        after
          :cleanup
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule TestModule do
             def run do
               case Map.get(%{}, :key) do
                 nil ->
                   :not_found

                 value ->
                   {:ok, value}

                 # trailing comment
               after
                 :cleanup
               rescue
                 _ -> :error
               end
             end
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule TestModule do
             def run do
               case Map.get(%{}, :key) do
                 nil ->
                   :not_found

                 value ->
                   {:ok, value}

                 # trailing comment
               after
                 :cleanup
               rescue
                 _ -> :error
               end
             end
           end
           """))
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule TestModule do
      def run do
        case Map.get(%{}, :key) do
          nil -> :not_found
          value -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves try-rescue unchanged" do
    input = """
    defmodule TestModule do
      def run do
        try do
          case Map.get(%{}, :key) do
            nil -> :not_found
            value -> {:ok, value}
          end
        after
          :cleanup
        rescue
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
