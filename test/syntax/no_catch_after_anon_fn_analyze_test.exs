defmodule Credence.Syntax.NoCatchAfterAnonFnAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoCatchAfterAnonFn

  defp analyze(code), do: NoCatchAfterAnonFn.analyze(code)

  test "flags catch after fn end" do
    code = """
    defmodule CatchAfterAnonFn do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        catch
          value -> value
        end
      end
    end
    """

    assert [%Issue{rule: :no_catch_after_anon_fn, meta: %{line: 6}}] = analyze(code)
  end

  test "flags after after fn end" do
    code = """
    defmodule AfterAnonFn do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        after
          :cleanup
        end
      end
    end
    """

    assert [%Issue{rule: :no_catch_after_anon_fn, meta: %{line: 6}}] = analyze(code)
  end

  test "flags a single-line expression too" do
    code = """
    defmodule OneLine do
      def run do
        Enum.map([1], fn x -> x end)
        catch
          v -> v
        end
      end
    end
    """

    assert [%Issue{rule: :no_catch_after_anon_fn, meta: %{line: 4}}] = analyze(code)
  end

  test "leaves good code alone" do
    # Normal code that parses fine
    assert analyze("""
           defmodule Good do
             def run do
               Enum.map([1, 2, 3], fn x -> x + 1 end)
             end
           end
           """) == []
  end

  test "leaves try/catch alone" do
    # Valid try/catch
    assert analyze("""
           defmodule GoodTry do
             def run do
               try do
                 Enum.map([1, 2, 3], fn x -> x + 1 end)
               catch
                 value -> value
               end
             end
           end
           """) == []
  end

  test "leaves receive/after alone" do
    # Valid receive/after
    assert analyze("""
           defmodule GoodReceive do
             def run do
               receive do
                 :ok -> :ok
               after
                 5000 -> :timeout
               end
             end
           end
           """) == []
  end

  # --- deliberately not flagged: the line scan cannot prove these are the bug ---

  test "no issue: a legal receive/after in a file that is broken elsewhere" do
    # The clause line above `after` ends in `end)`, so the line scan sees a
    # candidate — but wrapping it does not make the file parse, so we stand down
    # rather than mangle valid code.
    assert analyze("""
           defmodule M do
             def loop(l) do
               receive do
                 {:go, x} -> Enum.map(l, fn y -> y + x end)
               after
                 100 -> :timeout
               end
             end

             def broken do
               1 +
             end
           end
           """) == []
  end

  test "no issue: `catch` inside a heredoc following an `end)` line" do
    assert analyze("""
           defmodule M do
             def a do
               Enum.map([1], fn x -> x end)
               text = \"\"\"
           catch
           me
           \"\"\"

               text
             end
           end
           """) == []
  end

  test "no issue: the real bug plus an unrelated parse error" do
    # Wrapping repairs one of the two errors, so the source still would not
    # parse; a half-repair is not something we ship.
    assert analyze("""
           defmodule M do
             def run do
               Enum.map([1, 2, 3], fn x ->
                 x + 1
               end)
               catch
                 value -> value
               end
             end

             def broken do
               1 +
             end
           end
           """) == []
  end

  test "no issue: two candidate sites in one file" do
    # Two guesses, and the wraps would nest into each other — out of the safe core.
    assert analyze("""
           defmodule M do
             def a do
               Enum.map([1], fn x -> x end)
               catch
                 v -> v
               end
             end

             def b do
               Enum.map([1], fn x -> x end)
               catch
                 v -> v
               end
             end
           end
           """) == []
  end
end
