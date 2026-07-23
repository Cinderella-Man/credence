defmodule Credence.Semantic.NoRescueInExceptionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRescueInException

  # Verbatim from `Code.with_diagnostics/1` compiling a `rescue e in Exception`.
  @real_message "struct Exception is undefined (there is such module but it does not define a struct)"

  defp diag(position \\ {6, 9}) do
    %{severity: :warning, message: @real_message, position: position}
  end

  test "matches the diagnostic" do
    assert NoRescueInException.match?(diag())
  end

  test "ignores unrelated diagnostics" do
    refute NoRescueInException.match?(%{severity: :warning, message: "unrelated", position: {1, 1}})
  end

  test "ignores error severity" do
    refute NoRescueInException.match?(%{severity: :error, message: @real_message, position: {6, 9}})
  end

  test "attributes the issue to this rule" do
    assert NoRescueInException.to_issue(diag()).rule == :no_rescue_in_exception
  end

  test "sets the line in issue meta" do
    assert NoRescueInException.to_issue(diag({145, 9})).meta.line == 145
  end

  test "sets the line in issue meta when the position is a bare line" do
    assert NoRescueInException.to_issue(diag(145)).meta.line == 145
  end

  test "reports a rescue clause head spelled Exception" do
    source = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    assert NoRescueInException.should_report?(diag(), source)
  end

  test "reports a rescue clause head spelled Elixir.Exception" do
    source = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in Elixir.Exception ->
            {:error, e}
        end
      end
    end
    """

    assert NoRescueInException.should_report?(diag(), source)
  end

  # --- deliberately not reported: the fix would change a working answer ---

  test "no issue: a real exception struct keeps its narrow rescue" do
    source = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in ArgumentError ->
            {:error, e}
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: `in Exception` outside a rescue head is Enum.member?/2, not a struct match" do
    source = """
    defmodule Example do
      def run(x) do
        if x in Exception, do: :yes, else: :no
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: a cond clause is an expression, not a rescue head" do
    source = """
    defmodule Example do
      def run(x) do
        cond do
          x in Exception -> :yes
          true -> :no
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: bare Exception in a file that aliases the name may be a real struct" do
    source = """
    defmodule Example do
      def run do
        alias MyApp.Exception

        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: an `as:` alias binding the name Exception also blocks the fix" do
    source = """
    defmodule Example do
      def run do
        alias MyApp.Boom, as: Exception

        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: a multi-alias binding the name Exception also blocks the fix" do
    source = """
    defmodule Example do
      def run do
        alias MyApp.{Exception, Other}

        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  # `e in [Exception, ArgumentError]` warns too, but pruning the dead element
  # out of a list is a different rewrite than dropping the `in`. Left alone so
  # `check` never promises a repair `fix/2` will not make.
  test "no issue: a list of rescued types is out of the narrow core" do
    source = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in [Exception, ArgumentError] ->
            {:error, e}
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: already-plain rescue" do
    source = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end
      end
    end
    """

    refute NoRescueInException.should_report?(diag(), source)
  end

  test "no issue: source that does not parse" do
    refute NoRescueInException.should_report?(diag(), "defmodule Broken do")
  end
end
