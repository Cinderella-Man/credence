defmodule Credence.Semantic.NoUndefinedModuleInRescueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUndefinedModuleInRescue

  @not_implemented_msg "struct NotImplementedError is undefined (module NotImplementedError is not available or is yet to be defined). Make sure the module name is correct and has been specified in full (or that an alias has been defined)"

  defp fix(source, message \\ @not_implemented_msg, line \\ 1) do
    NoUndefinedModuleInRescue.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes undefined module from rescue clause list" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [NotImplementedError, RuntimeError] ->
            {:error, :exception}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [RuntimeError] ->
            {:error, :exception}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces single-module list with catch-all rescue" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [NotImplementedError] ->
            {:error, :exception}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e ->
            {:error, :exception}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [NotImplementedError, RuntimeError] ->
            {:error, :exception}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixed output is well-formed for catch-all case" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [NotImplementedError] ->
            {:error, :exception}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when module not in rescue list" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [RuntimeError] ->
            {:error, :exception}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "handles different undefined module" do
    msg =
      "struct BadStructError is undefined (module BadStructError is not available or is yet to be defined). Make sure the module name is correct and has been specified in full (or that an alias has been defined)"

    input = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [BadStructError, ArgumentError] ->
            {:error, :exception}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          {:ok, 1}
        rescue
          e in [ArgumentError] ->
            {:error, :exception}
        end
      end
    end
    """

    confirm_fix(fix(input, msg), expected)
  end
end
