defmodule Credence.Semantic.FixTruncatedSpecialFormFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTruncatedSpecialForm

  # All positions below are the real `Code.with_diagnostics/1` positions for
  # each fixture, not hand-counted columns.
  defp fix(source, message, position) do
    FixTruncatedSpecialForm.fix(source, %{
      severity: :error,
      message: message,
      position: position
    })
  end

  @module_msg "undefined variable \"__MODULE\""
  @env_msg "undefined variable \"__ENV\""
  @stacktrace_msg "undefined variable \"__STACKTRACE\""

  test "fixes both truncated __MODULE diagnostics, applied rightmost-first as the phase does" do
    input = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE)
        GenServer.start_link(__MODULE, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    expected = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    fixed =
      input
      |> fix(@module_msg, {6, 26})
      |> fix(@module_msg, {5, 37})

    confirm_fix(fixed, expected)
    assert valid_syntax?(fixed)
  end

  test "a single diagnostic fixes only its own occurrence" do
    input = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE)
        GenServer.start_link(__MODULE, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    expected = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE)
        GenServer.start_link(__MODULE__, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    confirm_fix(fix(input, @module_msg, {6, 26}), expected)
  end

  test "fixes truncated __ENV" do
    input = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV
    end
    """

    expected = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV__
    end
    """

    confirm_fix(fix(input, @env_msg, {2, 25}), expected)
    assert valid_syntax?(fix(input, @env_msg, {2, 25}))
  end

  test "fixes truncated __STACKTRACE inside rescue" do
    input = """
    defmodule Rescuer do
      def run(fun) do
        fun.()
      rescue
        e -> {e, __STACKTRACE}
      end
    end
    """

    expected = """
    defmodule Rescuer do
      def run(fun) do
        fun.()
      rescue
        e -> {e, __STACKTRACE__}
      end
    end
    """

    confirm_fix(fix(input, @stacktrace_msg, {5, 14}), expected)
  end

  test "leaves the same text inside a string literal untouched" do
    input = """
    defmodule Stringy do
      def note, do: "__MODULE is the truncated form"
      def broken, do: __MODULE
    end
    """

    expected = """
    defmodule Stringy do
      def note, do: "__MODULE is the truncated form"
      def broken, do: __MODULE__
    end
    """

    confirm_fix(fix(input, @module_msg, {3, 19}), expected)
  end

  test "leaves a legal __MODULE variable binding untouched" do
    input = """
    defmodule Bound do
      def ok do
        __MODULE = :mod
        IO.inspect(__MODULE)
      end

      def broken, do: __MODULE
    end
    """

    expected = """
    defmodule Bound do
      def ok do
        __MODULE = :mod
        IO.inspect(__MODULE)
      end

      def broken, do: __MODULE__
    end
    """

    confirm_fix(fix(input, @module_msg, {7, 19}), expected)
  end

  test "leaves an already-correct __MODULE__ and a :__MODULE atom untouched" do
    input = """
    defmodule Mixed do
      def broken, do: __MODULE
      def correct, do: __MODULE__.hello()
      def tag, do: :__MODULE
    end
    """

    expected = """
    defmodule Mixed do
      def broken, do: __MODULE__
      def correct, do: __MODULE__.hello()
      def tag, do: :__MODULE
    end
    """

    confirm_fix(fix(input, @module_msg, {2, 19}), expected)
  end

  test "no-ops when a stale position points at truncated text in data" do
    string_input = "defmodule StaleString do\n  def note, do: \"__MODULE\"\nend\n"
    atom_input = "defmodule StaleAtom do\n  def tag, do: :__MODULE\nend\n"

    confirm_fix(fix(string_input, @module_msg, {2, 18}), string_input)
    confirm_fix(fix(atom_input, @module_msg, {2, 17}), atom_input)
  end

  test "no-ops when the column does not sit on the truncated name" do
    input = """
    defmodule Mixed do
      def broken, do: __MODULE
    end
    """

    confirm_fix(fix(input, @module_msg, {2, 1}), input)
  end

  test "no-ops when the position points at an already-correct __MODULE__" do
    input = """
    defmodule Correct do
      def correct, do: __MODULE__.hello()
    end
    """

    confirm_fix(fix(input, @module_msg, {2, 20}), input)
  end

  test "no-ops on a bare-line position (no column to verify)" do
    input = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV
    end
    """

    confirm_fix(fix(input, @env_msg, 2), input)
  end

  test "no-ops when the line is out of range" do
    input = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV
    end
    """

    confirm_fix(fix(input, @env_msg, {99, 25}), input)
  end

  # End-to-end through the real phase: proves this rule wins the diagnostic
  # (priority 450, below fix_case_branch_assignment_scope's family claim at
  # 500) and that both occurrences are fixed from real compiler positions.
  test "the semantic phase fixes truncated __MODULE end-to-end" do
    input = """
    defmodule TruncatedDunderE2E do
      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE)
        GenServer.start_link(__MODULE, %{}, name: name)
      end
    end
    """

    expected = """
    defmodule TruncatedDunderE2E do
      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, %{}, name: name)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end
end
