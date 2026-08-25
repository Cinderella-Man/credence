defmodule Credence.Semantic.NoHallucinatedDatetimeZoneFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedDatetimeZone

  @real_message "unknown key .zone in expression:\n\n    dt.zone\n\nthe given type does not have the given key:\n\n    dynamic(%DateTime{\n      year: term(),\n      month: term(),\n      day: term(),\n      hour: term(),\n      minute: term(),\n      second: term(),\n      time_zone: term(),\n      zone_abbr: term(),\n      utc_offset: term(),\n      std_offset: term(),\n      microsecond: term(),\n      calendar: term()\n    })\n\nwhere \"dt\" was given the type:\n\n    # type: dynamic(%DateTime{})\n    # from: credence_check.ex:139:33\n    %DateTime{} = dt\n"

  defp fix(source, message, line) do
    NoHallucinatedDatetimeZone.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces .zone with .time_zone on the flagged variable" do
    input = """
    defmodule Example do
      def utc?(dt) when is_struct(dt, DateTime) do
        dt.zone == "Etc/UTC"
      end
    end
    """

    expected = """
    defmodule Example do
      def utc?(dt) when is_struct(dt, DateTime) do
        dt.time_zone == "Etc/UTC"
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def utc?(dt) when is_struct(dt, DateTime) do
        dt.zone == "Etc/UTC"
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "leaves .zone_abbr on the same variable untouched" do
    input = """
    defmodule Example do
      def label(dt) when is_struct(dt, DateTime) do
        {dt.zone, dt.zone_abbr}
      end
    end
    """

    expected = """
    defmodule Example do
      def label(dt) when is_struct(dt, DateTime) do
        {dt.time_zone, dt.zone_abbr}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "rewrites only code on the flagged line" do
    input = ~S'dt.zone <> "dt.zone" # dt.zone'
    expected = ~S'dt.time_zone <> "dt.zone" # dt.zone'

    confirm_fix(fix(input, @real_message, 1), expected)
  end

  test "only rewrites the flagged line, leaving a valid .zone on another line alone" do
    # Line 3 is the flagged DateTime hallucination. Line 7's `dt` is a different
    # struct that really has a :zone field — valid code the fix must not touch.
    input = """
    defmodule Example do
      def utc?(dt) when is_struct(dt, DateTime) do
        dt.zone == "Etc/UTC"
      end

      def region(dt) do
        dt.zone
      end
    end
    """

    expected = """
    defmodule Example do
      def utc?(dt) when is_struct(dt, DateTime) do
        dt.time_zone == "Etc/UTC"
      end

      def region(dt) do
        dt.zone
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "returns source unchanged when no .zone present" do
    input = """
    defmodule Example do
      def utc?(dt) when is_struct(dt, DateTime) do
        dt.time_zone == "Etc/UTC"
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message, 2), input)
  end

  # ═══════════════════════════════════════════════════════════════════
  # THE WITNESS — ledgered `:no_fixture` under T1. A *closed* struct type
  # is required: the `is_struct/2` guard form the other fixtures use
  # refines to an open map, and the compiler then emits nothing at all,
  # so no fixture in this file could witness. docs/22 T5.9.
  # ═══════════════════════════════════════════════════════════════════

  describe "witnesses its own failure mode through the real pipeline" do
    test "a closed %DateTime{} match emits the warning and the rule wins it" do
      source = """
      defmodule DatetimeZoneWitness do
        def f(%DateTime{} = dt), do: dt.zone
      end
      """

      diagnostics =
        case Credence.RuleHelpers.compile_and_capture(source) do
          {:ok, ds} -> ds
          {:error, ds} -> ds
        end

      assert Enum.any?(diagnostics, &NoHallucinatedDatetimeZone.match?/1)

      result = Credence.fix(source)
      assert {NoHallucinatedDatetimeZone, 1} in result.applied_rules
      assert result.code =~ "dt.time_zone"
      assert Credence.RuleCase.compiles?(result.code)
    end

    test "the is_struct/2 guard form emits nothing — which is why this was unwitnessed" do
      # Not a curiosity: it is the reason the ledger entry existed. `is_struct(dt,
      # DateTime)` refines to an OPEN map, so the type checker has no closed
      # struct to check the key against and says nothing.
      source = """
      defmodule DatetimeZoneOpenMap do
        def f(dt) when is_struct(dt, DateTime), do: dt.zone
      end
      """

      assert Credence.RuleHelpers.compile_and_capture(source) == {:ok, []}
    end
  end
end
