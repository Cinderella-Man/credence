defmodule Credence.Semantic.NoUnreachableCatchAfterRescueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.NoUnreachableCatchAfterRescue

  # Real message shape captured from `Code.with_diagnostics` on this Elixir;
  # the line it names is the shadowing `rescue` catch-all clause.
  defp message(previous_line) do
    "this clause cannot match because a previous clause at line #{previous_line} " <>
      "matches the same pattern as this clause"
  end

  defp fix(source, target_line, previous_line) do
    NoUnreachableCatchAfterRescue.fix(source, %{
      severity: :warning,
      message: message(previous_line),
      position: target_line
    })
  end

  @buggy_source """
  defmodule CredenceUnreachableCatchFixRepro do
    def run(f) do
      try do
        f.()
      rescue
        e -> {:error, e}
      catch
        :error, reason -> {:error, reason}
      end
    end
  end
  """

  test "removes the dead clause and the emptied catch section" do
    expected = """
    defmodule CredenceUnreachableCatchFixRepro do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(@buggy_source, 8, 6), expected)
  end

  test "fixed output is well-formed and no longer warns" do
    assert valid_syntax?(fix(@buggy_source, 8, 6))

    fixed = fix(@buggy_source, 8, 6)
    {:ok, diags} = RuleHelpers.compile_and_capture(fixed)
    refute Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)
  end

  test "the semantic phase applies the fix end to end" do
    expected = """
    defmodule CredenceUnreachableCatchFixRepro do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(@buggy_source), expected)
  end

  test "keeps the :exit clause and the catch section" do
    source = """
    defmodule CredenceUnreachableCatchKeepsExit do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :error, reason -> {:error, reason}
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCatchKeepsExit do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), expected)
  end

  test "removes the dead clause from a def-level rescue body" do
    source = """
    defmodule CredenceUnreachableCatchDefLevel do
      def run(f) do
        f.()
      rescue
        e -> {:error, e}
      catch
        :error, reason -> {:error, reason}
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCatchDefLevel do
      def run(f) do
        f.()
      rescue
        e -> {:error, e}
      end
    end
    """

    confirm_fix(fix(source, 7, 5), expected)
  end

  test "removes the dead clause when the rescue catch-all is the second rescue clause" do
    source = """
    defmodule CredenceUnreachableCatchSecondRescue do
      def run(f) do
        try do
          f.()
        rescue
          e in RuntimeError -> {:rt, e}
          e -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCatchSecondRescue do
      def run(f) do
        try do
          f.()
        rescue
          e in RuntimeError -> {:rt, e}
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(source, 9, 7), expected)
  end

  test "removes the dead clause under an underscore rescue catch-all" do
    source = """
    defmodule CredenceUnreachableCatchUnderscoreRescue do
      def run(f) do
        try do
          f.()
        rescue
          _ -> :oops
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCatchUnderscoreRescue do
      def run(f) do
        try do
          f.()
        rescue
          _ -> :oops
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), expected)
  end

  test "keeps the else and after sections when the catch section is emptied" do
    source = """
    defmodule CredenceUnreachableCatchElseAfter do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        else
          {:ok, v} -> v
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCatchElseAfter do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        else
          {:ok, v} -> v
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), expected)
    assert valid_syntax?(fix(source, 8, 6))
  end

  test "leaves a single-pattern catch :error -> alone (it catches throw(:error))" do
    source = """
    defmodule CredenceUnreachableCatchThrowFix do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :error -> :caught_throw
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), source)
  end

  test "leaves a guarded catch clause alone" do
    source = """
    defmodule CredenceUnreachableCatchGuardedFix do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :error, reason when is_atom(reason) -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), source)
  end

  test "leaves the catch clause alone when the rescue narrows to one exception" do
    source = """
    defmodule CredenceUnreachableCatchNarrowRescueFix do
      def run(f) do
        try do
          f.()
        rescue
          e in RuntimeError -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), source)
  end

  test "leaves an :exit clause alone" do
    source = """
    defmodule CredenceUnreachableCatchExitFix do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    confirm_fix(fix(source, 8, 6), source)
  end

  test "leaves a try with no rescue section alone" do
    source = """
    defmodule CredenceUnreachableCatchNoRescueFix do
      def run(f) do
        try do
          f.()
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(source, 6, 4), source)
  end

  test "leaves the source alone when the flagged line holds no catch clause" do
    confirm_fix(fix(@buggy_source, 6, 6), @buggy_source)
  end

  test "leaves the source alone when the named previous line is not the rescue catch-all" do
    confirm_fix(fix(@buggy_source, 8, 4), @buggy_source)
  end

  test "leaves a duplicate case clause carrying the same warning alone" do
    source = """
    defmodule CredenceUnreachableCatchDuplicateCaseFix do
      def run(x) do
        case x do
          :a -> 1
          :a -> 2
          _ -> 3
        end
      end
    end
    """

    confirm_fix(fix(source, 5, 4), source)
  end

  test "leaves the source alone when two candidate clauses share the flagged line" do
    source = """
    defmodule CredenceUnreachableCatchAmbiguousFix do
      def run(f, g) do
        {(try do f.() rescue e -> {:e, e} catch :error, r -> {:c, r} end), (try do g.() rescue e -> {:e, e} catch :error, r -> {:c, r} end)}
      end
    end
    """

    confirm_fix(fix(source, 3, 3), source)
  end

  test "leaves the source alone when the fix is asked for an unparseable file" do
    source = """
    defmodule CredenceUnreachableCatchBroken do
      def run(f) do
        try do
    end
    """

    confirm_fix(fix(source, 8, 6), source)
  end

  test "ignores a diagnostic without a position" do
    result =
      NoUnreachableCatchAfterRescue.fix(@buggy_source, %{
        severity: :warning,
        message: message(6),
        position: nil
      })

    confirm_fix(result, @buggy_source)
  end
end
