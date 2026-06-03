defmodule Credence.Pattern.NoAttrBeforeDefmodule do
  @moduledoc """
  Correctness rule: Detects documentation/spec module attributes
  (`@moduledoc`, `@doc`, `@spec`, `@type`, `@typep`) placed at the top level
  **before** a `defmodule`, and moves them inside that module. A module
  attribute outside a module does not compile:

      cannot invoke @/1 outside module

  LLMs frequently emit `@moduledoc "..."` (and friends) just above the
  `defmodule` they belong to. The fix relocates the contiguous run of such
  attributes that immediately precedes a `defmodule` to the top of that
  module's body, in their original order.

  ## Scope (deliberately narrow)

    * Only **doc/spec** attributes are moved (`@moduledoc`, `@doc`, `@spec`,
      `@type`, `@typep`) — never `@impl`, `@derive`, `@behaviour`, etc., whose
      placement carries ordering semantics.
    * Only when an actual `defmodule` follows. Bare code with no module is left
      alone — we never invent a module.
    * Nothing is ever deleted: existing attributes inside the module are kept
      as-is (no de-duplication).

  ## Bad

      @moduledoc "Greets people"
      defmodule Greeter do
        def hi, do: :ok
      end

  ## Good

      defmodule Greeter do
        @moduledoc "Greets people"
        def hi, do: :ok
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @movable [:moduledoc, :doc, :spec, :type, :typep]

  @impl true
  def check(ast, _opts) do
    case relocation(ast) do
      {:ok, [first_attr | _], _kept, _dm, _rest} ->
        [build_issue(first_attr)]

      :no ->
        []
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source)
    Credence.RuleHelpers.patches_from_ast_transform(ast, source, &move_attrs/1)
  end

  defp move_attrs(ast) do
    case relocation(ast) do
      {:ok, attrs, kept, dm, rest} ->
        {:__block__, block_meta(ast), kept ++ [prepend_body(dm, attrs) | rest]}

      :no ->
        ast
    end
  end

  defp block_meta({:__block__, meta, _}), do: meta
  defp block_meta(_), do: []

  # Finds the contiguous run of movable attrs immediately preceding the first
  # top-level `defmodule`. Returns {:ok, attrs, kept_before, defmodule, rest}.
  defp relocation({:__block__, _, children}) when is_list(children) do
    case Enum.find_index(children, &defmodule?/1) do
      nil ->
        :no

      idx ->
        {before_dm, [dm | rest]} = Enum.split(children, idx)
        {kept, attrs} = split_trailing_attrs(before_dm)
        if attrs == [], do: :no, else: {:ok, attrs, kept, dm, rest}
    end
  end

  defp relocation(_), do: :no

  defp split_trailing_attrs(list) do
    {rev_attrs, rev_kept} = Enum.split_while(Enum.reverse(list), &movable_attr?/1)
    {Enum.reverse(rev_kept), Enum.reverse(rev_attrs)}
  end

  defp prepend_body({:defmodule, dm_meta, [alias_node, [{do_key, body}]]}, attrs) do
    new_body = {:__block__, [], attrs ++ body_statements(body)}
    {:defmodule, dm_meta, [alias_node, [{do_key, new_body}]]}
  end

  # Unexpected defmodule shape — leave it untouched (no fix rather than a wrong one).
  defp prepend_body(other, _attrs), do: other

  defp body_statements({:__block__, _, stmts}) when is_list(stmts) and length(stmts) > 1,
    do: stmts

  defp body_statements(single), do: [single]

  defp movable_attr?({:@, _, [{name, _, _}]}) when name in @movable, do: true
  defp movable_attr?(_), do: false

  defp defmodule?({:defmodule, _, _}), do: true
  defp defmodule?(_), do: false

  defp build_issue({:@, meta, _}) do
    %Issue{
      rule: :no_attr_before_defmodule,
      message:
        "Module attribute appears before `defmodule` (does not compile). " <>
          "Move it inside the module block.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
