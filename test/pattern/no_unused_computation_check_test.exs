defmodule Credence.Pattern.NoUnusedComputationCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnusedComputation

  # ── positive cases (should flag) ────────────────────────────────────

  test "flags _n = length(list)" do
    assert flagged?(NoUnusedComputation, """
           defmodule Flagged do
             def process(list) do
               _n = length(list)
               Enum.reverse(list)
             end
           end
           """)
  end

  test "flags _count = String.length(s)" do
    assert flagged?(NoUnusedComputation, """
           defmodule Flagged do
             def run(s) do
               _count = String.length(s)
               String.upcase(s)
             end
           end
           """)
  end

  test "flags _g = String.graphemes(s)" do
    assert flagged?(NoUnusedComputation, """
           defmodule Flagged do
             def run(s) do
               _g = String.graphemes(s)
               String.trim(s)
             end
           end
           """)
  end

  test "flags bare _ = length(list)" do
    assert flagged?(NoUnusedComputation, """
           defmodule Flagged do
             def process(list) do
               _ = length(list)
               Enum.reverse(list)
             end
           end
           """)
  end

  test "flags _x = abs(n)" do
    assert flagged?(NoUnusedComputation, """
           defmodule Flagged do
             def run(n) do
               _x = abs(n)
               n + 1
             end
           end
           """)
  end

  test "flags _rev = Enum.reverse(list)" do
    assert flagged?(NoUnusedComputation, """
           defmodule Flagged do
             def run(list) do
               _rev = Enum.reverse(list)
               Enum.sort(list)
             end
           end
           """)
  end

  # ── negative cases (should NOT flag) ────────────────────────────────

  test "leaves used variable alone" do
    assert clean?(NoUnusedComputation, """
           defmodule Clean do
             def process(list) do
               n = length(list)
               n + 1
             end
           end
           """)
  end

  test "leaves impure call (IO.puts) alone" do
    assert clean?(NoUnusedComputation, """
           defmodule Clean do
             def run do
               _n = IO.puts("hello")
               :ok
             end
           end
           """)
  end

  test "leaves unknown function call alone" do
    assert clean?(NoUnusedComputation, """
           defmodule Clean do
             def run(x) do
               _n = some_unknown_function(x)
               :ok
             end
           end
           """)
  end

  test "leaves _-prefixed with non-call RHS alone" do
    assert clean?(NoUnusedComputation, """
           defmodule Clean do
             def run do
               _n = 42
               :ok
             end
           end
           """)
  end
end
