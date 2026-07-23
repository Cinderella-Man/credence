defmodule Credence.Semantic.NoUnusedTypeDeclaration do
  @moduledoc """
  Deletes the `@typep` declaration the compiler has proven nothing references.

  A private type that is never mentioned in a spec, another type, or a callback
  is dead metadata — it has no runtime and no compile-time effect beyond the
  warning it raises, which fails a `--warnings-as-errors` build:

      warning: type step/0 is unused

  Only `@typep` can produce this warning (`@type` and `@opaque` are exported, so
  the compiler never calls them unused — checked), and the compiler has already
  done the reachability analysis, so removing the declaration is
  behaviour-preserving.

  ## Bad

      defmodule Saga do
        @typep step :: %{name: atom()}

        def new, do: %Saga{}
      end

  ## Good

      defmodule Saga do
        def new, do: %Saga{}
      end

  An immediately preceding `@typedoc` is removed along with it: it documents
  exactly the declaration being deleted, it is discarded by the compiler anyway
  for a private type ("@typedoc's are always discarded for private types"), and
  leaving it behind would swap one warning for another ("module attribute
  @typedoc was set but no type follows it" — checked).

  ## What it deliberately does NOT touch

  The declaration is located by *name, arity and the line the warning names*, and
  only among the direct children of a `defmodule` body. Everything else is left
  alone:

    * a same-named `@typep` in another module in the same file, or a same-named
      declaration of a different arity — the flagged line pins exactly one.
    * a `@typep` written inside `quote do … end`. It is not a direct child of the
      module body, and deleting it would change every module that uses the macro,
      not just the one the warning came from.
    * a module whose whole body is the declaration (no `:__block__`), and a body
      that would be left empty by the removal — an empty `defmodule` body is not
      worth rendering.
    * any shape the warning names but the walk cannot pin down to exactly one
      declaration.

  `should_report?/2` re-runs `fix/2`, so a diagnostic the rewrite declines is
  never reported as an issue either — the check and the fix always agree.
  """

  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_re ~r{^type (\w+)/(\d+) is unused$}

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics this rule can actually delete. Which declaration the
  warning names is decided by re-running the rewrite, so a shape the fix leaves
  alone never becomes an issue.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unused_type_declaration,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{severity: :warning, message: msg} = diagnostic) when is_binary(msg) do
    with [_, name, arity] <- Regex.run(@match_re, msg),
         target_line when is_integer(target_line) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, new_ast} <-
           delete_typep(ast, String.to_atom(name), String.to_integer(arity), target_line) do
      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Delete the flagged declaration from the body of the module that owns the
  # flagged line. Returns `:error` unless exactly one module body yielded a
  # deletion, so an ambiguous file leaves the source untouched.
  defp delete_typep(ast, name, arity, line) do
    {new_ast, deleted} =
      Macro.prewalk(ast, 0, fn
        {:defmodule, meta, [aliased, blocks]} = node, acc when is_list(blocks) ->
          case drop_from_body(blocks, name, arity, line) do
            {:ok, new_blocks} -> {{:defmodule, meta, [aliased, new_blocks]}, acc + 1}
            :none -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if deleted == 1, do: {:ok, new_ast}, else: :error
  end

  # Drop the declaration (and its `@typedoc`) from a `do:` body that is a
  # `:__block__` of sibling expressions.
  defp drop_from_body(blocks, name, arity, line) do
    with index when is_integer(index) <- Enum.find_index(blocks, &do_block?/1),
         {key, {:__block__, body_meta, children}} <- Enum.at(blocks, index),
         true <- is_list(children),
         at when is_integer(at) <-
           Enum.find_index(children, &target_typep?(&1, name, arity, line)),
         [_ | _] = kept <- drop_declaration(children, at) do
      {:ok, List.replace_at(blocks, index, {key, {:__block__, body_meta, kept}})}
    else
      _ -> :none
    end
  end

  defp do_block?({{:__block__, _, [:do]}, _value}), do: true
  defp do_block?(_), do: false

  # Remove the declaration at `index`, plus the `@typedoc` right in front of it.
  defp drop_declaration(children, index) do
    kept = List.delete_at(children, index)

    if index > 0 and typedoc?(Enum.at(children, index - 1)) do
      List.delete_at(kept, index - 1)
    else
      kept
    end
  end

  defp typedoc?({:@, _, [{:typedoc, _, [_]}]}), do: true
  defp typedoc?(_), do: false

  # Exactly `@typep <name>(<arity args>) :: …` on the flagged line.
  defp target_typep?({:@, meta, [{:typep, _, [{:"::", _, [head | _]}]}]}, name, arity, line) do
    Keyword.get(meta, :line) == line and typep_head?(head, name, arity)
  end

  defp target_typep?(_node, _name, _arity, _line), do: false

  defp typep_head?({head, _, nil}, name, 0) when is_atom(head), do: head == name

  defp typep_head?({head, _, args}, name, arity) when is_atom(head) and is_list(args) do
    head == name and length(args) == arity
  end

  defp typep_head?(_head, _name, _arity), do: false

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
