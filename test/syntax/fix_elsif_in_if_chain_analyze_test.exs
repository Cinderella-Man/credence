defmodule Credence.Syntax.FixElsifInIfChainAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixElsifInIfChain

  defp analyze(code), do: FixElsifInIfChain.analyze(code)

  test "flags the unparseable code" do
    code = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    assert [%Issue{rule: :fix_elsif_in_if_chain}] = analyze(code)
  end

  test "reports the line the elsif sits on" do
    code = ~S"""
    defmodule M do
      def check(x) do
        if x > 0 do
          :pos
        elsif x < 0 do
          :neg
        else
          :zero
        end
      end
    end
    """

    assert [%Issue{meta: %{line: 5}}] = analyze(code)
  end

  test "reports one issue per chain, however many elsif branches it holds" do
    code = ~S"""
    if a do
      1
    elsif b do
      2
    elsif c do
      3
    else
      4
    end
    """

    assert [%Issue{rule: :fix_elsif_in_if_chain}] = analyze(code)
  end

  test "leaves good code alone" do
    code = ~S"""
    defmodule Foo do
      def check(x) do
        cond do
          x > 0 -> :positive
          true -> :non_positive
        end
      end
    end
    """

    assert analyze(code) == []
  end

  # `analyze/1` asks exactly what `fix/1` asks, so none of the shapes the fix
  # refuses (see the rule's moduledoc) is reported as a problem we won't solve.

  test "no issue for a multi-line if condition (cannot be read off one line)" do
    code = ~S"""
    if a and
         b do
      1
    elsif c do
      2
    else
      3
    end
    """

    assert analyze(code) == []
  end

  test "no issue for a multi-line elsif condition" do
    code = ~S"""
    if a do
      1
    elsif b and
         c do
      2
    else
      3
    end
    """

    assert analyze(code) == []
  end

  test "no issue for a one-liner elsif (`, do:`)" do
    code = ~S"""
    if a do
      1
    elsif b, do: 2
    else
      3
    end
    """

    assert analyze(code) == []
  end

  test "no issue when the else carries a trailing comment" do
    code = ~S"""
    if a do
      1
    elsif b do
      2
    else # note
      3
    end
    """

    assert analyze(code) == []
  end

  test "no issue when the if header is not at the start of its line" do
    code = ~S"""
    r = if a do
      1
    elsif b do
      2
    end
    """

    assert analyze(code) == []
  end

  test "no issue when the chain has no terminating end at its own indent" do
    code = ~S"""
    def f(a, b) do
      if a do
        1
      elsif b do
        2
    end
    """

    assert analyze(code) == []
  end

  test "no issue when a branch body holds a heredoc (re-indenting changes its value)" do
    code = """
    if a do
      x = \"""
        content
      \"""
      x
    elsif b do
      2
    else
      3
    end
    """

    assert analyze(code) == []
  end

  test "no issue when a branch body holds a string spanning lines" do
    code = ~S"""
    if a do
      x = "hello
    world"
      x
    elsif b do
      2
    else
      3
    end
    """

    assert analyze(code) == []
  end

  test "no issue for an elsif that is documentation inside a heredoc" do
    code = """
    defmodule M do
      @moduledoc \"""
      Bad:

          if a do
            1
          elsif b do
            2
          end
      \"""
      def f, do: :ok
    end

    x =
    """

    assert analyze(code) == []
  end
end
