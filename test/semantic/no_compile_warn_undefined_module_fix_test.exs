defmodule Credence.Semantic.NoCompileWarnUndefinedModuleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoCompileWarnUndefinedModule

  @message "MyApp.Repo.insert!/1 is undefined (module MyApp.Repo is not available or is yet to be defined)"

  defp fix(source, message \\ @message, line \\ 1) do
    NoCompileWarnUndefinedModule.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "inserts @compile attribute after defmodule do" do
    input = """
    defmodule Factory do
      use Agent

      def start do
        {:ok, _pid} = Agent.start_link(fn -> %{sequences: %{}} end, name: __MODULE__)
      end

      defp do_insert(factory_name, overrides) do
        s = do_build(factory_name, overrides)
        MyApp.Repo.insert!(s)
      end
    end
    """

    expected = """
    defmodule Factory do
      @compile {:no_warn_undefined, MyApp.Repo}
      use Agent

      def start do
        {:ok, _pid} = Agent.start_link(fn -> %{sequences: %{}} end, name: __MODULE__)
      end

      defp do_insert(factory_name, overrides) do
        s = do_build(factory_name, overrides)
        MyApp.Repo.insert!(s)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Factory do
      use Agent

      defp do_insert(factory_name, overrides) do
        s = do_build(factory_name, overrides)
        MyApp.Repo.insert!(s)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "extracts different module names from diagnostic" do
    input = """
    defmodule MyFactory do
      def insert_thing do
        SomeApp.Repo.insert!(%{})
      end
    end
    """

    msg = "SomeApp.Repo.insert!/1 is undefined (module SomeApp.Repo is not available or is yet to be defined)"

    expected = """
    defmodule MyFactory do
      @compile {:no_warn_undefined, SomeApp.Repo}
      def insert_thing do
        SomeApp.Repo.insert!(%{})
      end
    end
    """

    confirm_fix(fix(input, msg), expected)
  end

  test "returns source unchanged when @compile already present" do
    input = """
    defmodule Factory do
      @compile {:no_warn_undefined, MyApp.Repo}
      use Agent

      defp do_insert(factory_name, overrides) do
        s = do_build(factory_name, overrides)
        MyApp.Repo.insert!(s)
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "handles nested module names" do
    input = """
    defmodule MyFactory do
      def insert do
        MyApp.Internal.Repo.insert!(%{})
      end
    end
    """

    msg = "MyApp.Internal.Repo.insert!/1 is undefined (module MyApp.Internal.Repo is not available or is yet to be defined)"

    expected = """
    defmodule MyFactory do
      @compile {:no_warn_undefined, MyApp.Internal.Repo}
      def insert do
        MyApp.Internal.Repo.insert!(%{})
      end
    end
    """

    confirm_fix(fix(input, msg), expected)
  end
end
