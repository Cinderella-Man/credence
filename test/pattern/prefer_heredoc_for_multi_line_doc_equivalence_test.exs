defmodule Credence.Pattern.PreferHeredocForMultiLineDocEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call, doc-observation) — compare `Code.fetch_docs/1` of before/after.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferHeredocForMultiLineDoc

  # Firing snippets lifted from prefer_heredoc_for_multi_line_doc_check_test.exs:
  #   defmodule Example do
  #       @doc "Line one.\n\nLine two.\nLine three."
  #       def foo, do: :ok
  #     end
  #   defmodule Example do
  #       @moduledoc "Module for things.\nDoes stuff."
  #       def foo, do: :ok
  #     end
  #   defmodule Example do
  #       @typedoc "A custom type.\nWith details."
  #       @type t :: atom()
  #     end

  test "prefer_heredoc_for_multi_line_doc: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: PreferHeredocForMultiLineDoc,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
