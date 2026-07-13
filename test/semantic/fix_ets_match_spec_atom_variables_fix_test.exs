defmodule Credence.Semantic.FixEtsMatchSpecAtomVariablesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixEtsMatchSpecAtomVariables

  @real_diag_msg "invalid syntax found on credence_check.ex:154:42:\n     error: unexpected token: \"$\" (column 42, code point U+0024)\n     │\n 154 │         {{:'$1', :'$2', :'_}, [{:'=<', :'$2', cutoff}], [true]}\n     │                                          ^\n     │\n     └─ credence_check.ex:154:42"

  defp fix(source, message \\ @real_diag_msg, line \\ 154) do
    FixEtsMatchSpecAtomVariables.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes match spec atom variables to charlist sigils" do
    input = """
    defmodule MatchSpecAtomVars do
      def find_expired(tid, cutoff) do
        :ets.select(tid, [
          {{:'$1', :'$2', :_}, [{:'=<', :'$2', cutoff}], [true]}
        ])
      end

      def prune_expired(tid, cutoff) do
        :ets.select_delete(tid, [
          {{:'$1', :'$2', :_}, [{:'=<', :'$2', cutoff}], [true]}
        ])
      end
    end
    """

    expected = """
    defmodule MatchSpecAtomVars do
      def find_expired(tid, cutoff) do
        :ets.select(tid, [
          {{~c"$1", ~c"$2", :_}, [{:'=<', ~c"$2", cutoff}], [true]}
        ])
      end

      def prune_expired(tid, cutoff) do
        :ets.select_delete(tid, [
          {{~c"$1", ~c"$2", :_}, [{:'=<', ~c"$2", cutoff}], [true]}
        ])
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MatchSpecAtomVars do
      def find_expired(tid, cutoff) do
        :ets.select(tid, [
          {{:'$1', :'$2', :_}, [{:'=<', :'$2', cutoff}], [true]}
        ])
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
