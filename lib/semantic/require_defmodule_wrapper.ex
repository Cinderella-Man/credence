defmodule Credence.Semantic.RequireDefmoduleWrapper do
  @moduledoc """
  The canonical "module attributes / code outside a `defmodule`" rule.

  Matches the Elixir compiler diagnostic emitted when `@moduledoc`/`@doc`/
  `@spec` (or a top-level `def`/`defp`) appear at file scope with no enclosing
  module (`cannot invoke @/1 outside module`, `... outside module`) and repairs
  it in one of two ways:

    * **No module at all** → wrap the whole source in `defmodule Solution do …
      end`.
    * **Doc/spec attributes orphaned ABOVE an existing `defmodule`** → MOVE that
      contiguous run of attributes inside the module (their original order,
      prepended to the body). Wrapping would be wrong here — it nests the
      existing module and mis-attaches the attributes.

  This is a SEMANTIC-round rule by design: the offending code PARSES but does not
  COMPILE, so it is diagnostic-driven (the syntax round is for code that won't
  parse; the pattern round is skipped for code that won't compile). It supersedes
  the redundant rules the tunex evolution runs generated for this one concern —
  `Syntax.NoOrphanedModuleAttributes`, `Syntax.WrapBareModuleAttrsInDefmodule`,
  `Syntax.PreferDefmoduleWrapper`, `Semantic.NoDocSpecOutsideModule`,
  `Semantic.PreferDefmoduleWrapper` — and the dead Pattern-round
  `NoAttrBeforeDefmodule` (whose fix never fired, since the input never compiles).
  Its move-into-module logic now lives here, where the round can actually run it.
  """
  use Credence.Semantic.Rule

  alias Credence.{Issue, RuleHelpers}

  # Doc/spec attributes that are safe to relocate. Never `@impl`/`@behaviour`/
  # `@derive` etc. — their placement carries ordering semantics.
  @movable [:moduledoc, :doc, :spec, :type, :typep]

  @impl true
  def match?(%{message: message}) when is_binary(message) do
    String.contains?(message, "outside module")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :require_defmodule_wrapper,
      message: "Top-level code must be wrapped in a defmodule",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case parse(source) do
      {:ok, ast} ->
        case relocation(ast) do
          # Attrs orphaned above an existing module → move them inside it.
          {:ok, _attrs, _kept, _dm, _rest} ->
            patches = RuleHelpers.patches_from_ast_transform(ast, source, &move_attrs/1)
            Sourceror.patch_string(source, patches)

          :no ->
            wrap_or_decline(source)
        end

      :error ->
        wrap_or_decline(source)
    end
  end

  # No movable attrs to relocate: wrap bare code, but DECLINE if a `defmodule`
  # already exists (wrapping would nest it — leave the diagnostic for that case).
  defp wrap_or_decline(source) do
    if has_defmodule?(source) do
      source
    else
      "defmodule Solution do\n" <> String.trim_trailing(source) <> "\nend\n"
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  defp has_defmodule?(source), do: Regex.match?(~r/^\s*defmodule\b/m, source)

  # ── Move orphaned attrs into the following module (ported from the retired
  #    Pattern.NoAttrBeforeDefmodule; operates on the Sourceror tree) ──────────

  defp move_attrs(ast) do
    case relocation(ast) do
      {:ok, attrs, kept, dm, rest} ->
        {:__block__, block_meta(ast), kept ++ [prepend_body(dm, attrs) | rest]}

      :no ->
        ast
    end
  end

  defp block_meta({:__block__, meta, _}), do: meta

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
    existing_stmts = body_statements(body)
    # Drop incoming attrs that would duplicate an attribute already inside the
    # module (the inner one takes precedence).  Exception: a real @moduledoc
    # being moved in should REPLACE a `@moduledoc false` — keep the incoming one
    # and strip the false one below.
    existing_attrs = existing_attrs(existing_stmts)
    real_moduledoc_incoming = has_real_moduledoc?(attrs)

    filtered_attrs =
      Enum.filter(attrs, fn attr ->
        identity = attr_identity(attr)

        cond do
          is_nil(identity) ->
            true

          not MapSet.member?(existing_attrs, identity) ->
            true

          # @moduledoc false in body + real @moduledoc incoming → replace false with real
          identity == :moduledoc and real_moduledoc_incoming and
              moduledoc_false_in?(existing_stmts) ->
            true

          true ->
            false
        end
      end)

    # If we kept a real @moduledoc from the incoming attrs, strip any inner
    # @moduledoc false to avoid a duplicate-attribute warning.
    cleaned =
      if real_moduledoc_incoming do
        Enum.reject(existing_stmts, &moduledoc_false?/1)
      else
        existing_stmts
      end

    new_body = {:__block__, [], filtered_attrs ++ cleaned}
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

  # True when attrs list contains a @moduledoc with real content (not false).
  defp has_real_moduledoc?(attrs) do
    Enum.any?(attrs, fn
      {:@, _, [{:moduledoc, _, [{:__block__, _, [val]}]}]} when is_binary(val) -> true
      {:@, _, [{:moduledoc, _, [val]}]} when is_binary(val) -> true
      _ -> false
    end)
  end

  # True for `@moduledoc false`.
  defp moduledoc_false?({:@, _, [{:moduledoc, _, [{:__block__, _, [false]}]}]}), do: true
  defp moduledoc_false?(_), do: false

  # Returns a MapSet of movable attribute identities already present in the body.
  defp existing_attrs(stmts) do
    stmts
    |> Enum.map(&attr_identity/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp attr_identity({:@, _, [{name, _, [{:"::", _, [{target, _, args}, _]}]}]})
       when name in [:spec, :type, :typep] and is_atom(target) and is_list(args),
       do: {name, target, length(args)}

  defp attr_identity(attr), do: attr_name(attr)

  # Extracts the attribute name from a `@name ...` AST node, or nil.
  defp attr_name({:@, _, [{name, _, _}]}) when name in @movable, do: name
  defp attr_name(_), do: nil

  # True when any statement in `stmts` is `@moduledoc false`.
  defp moduledoc_false_in?(stmts), do: Enum.any?(stmts, &moduledoc_false?/1)

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
