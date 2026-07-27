defmodule Credence.Semantic.FixUndefinedTypeTInSpec do
  @moduledoc """
  Inserts a `@type t :: %__MODULE__{...}` definition in struct modules that
  reference `t()` in a `@spec` without defining `@type t`.

  LLMs frequently generate `@spec f() :: t()` in struct modules without
  declaring `@type t`, causing the compiler to emit:

      type t/0 is undefined (no such type in Module)

  This rule detects that diagnostic and — when the module defines a struct via
  `defstruct` — inserts `@type t :: %__MODULE__{field: list(), ...}` right
  after the `defstruct` declaration so the spec compiles.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "type t/0 is undefined"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_undefined_type_t_in_spec,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    if String.contains?(msg, @match_substring) do
      with {:ok, ast} <- Sourceror.parse_string(source),
           {:defstruct, _, [fields_arg]} <- find_defstruct(ast),
           [_ | _] = fields <- extract_fields(fields_arg),
           false <- has_type_t?(ast) do
        insert_type_t(ast, fields)
      else
        _ -> source
      end
    else
      source
    end
  end

  def fix(source, _diagnostic), do: source

  # Walk the AST looking for a `defstruct` call.
  defp find_defstruct(ast) do
    case Macro.prewalk(ast, nil, fn
           {:defstruct, _, _} = node, _acc -> {node, node}
           node, acc -> {node, acc}
         end) do
      {_, nil} -> nil
      {_, found} -> found
    end
  end

  # Extract field names from the defstruct argument.
  #
  # Two Sourceror shapes:
  #   - Keyword list: `[{:__block__, [format: :keyword], [:field]}, default]` pairs
  #   - Plain list:   `{:__block__, _, [[{:__block__, _, [:field]}, ...]]}`
  defp extract_fields(fields_arg) when is_list(fields_arg) do
    case fields_arg do
      [{{:__block__, meta, [_]}, _} | _] = kw_pairs when is_list(meta) ->
        if Keyword.get(meta, :format) == :keyword do
          Enum.map(kw_pairs, fn {{:__block__, _, [name]}, _} -> name end)
        else
          []
        end

      _ ->
        if Keyword.keyword?(fields_arg), do: Keyword.keys(fields_arg), else: []
    end
  end

  defp extract_fields({:__block__, _, [inner_list]}) when is_list(inner_list) do
    Enum.map(inner_list, fn
      {:__block__, _, [name]} -> name
      name when is_atom(name) -> name
    end)
  end

  defp extract_fields(_), do: []

  # Check whether the module already has `@type t`.
  defp has_type_t?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{:type, _, [{:"::", _, [{:t, _, nil} | _]} | _]} | _]} = node, _ ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Build the `@type t` AST node and insert it after defstruct in the module body.
  defp insert_type_t(ast, fields) do
    type_attr = build_type_attr(fields)

    result =
      Macro.prewalk(ast, fn
        {:defmodule, mod_meta, [name, body_kw]} when is_list(body_kw) ->
          new_body_kw =
            Enum.map(body_kw, fn
              {{:__block__, do_meta, [:do]}, {:__block__, block_meta, stmts}} ->
                new_stmts =
                  Enum.flat_map(stmts, fn
                    {:defstruct, _, _} = ds -> [ds, type_attr]
                    other -> [other]
                  end)

                {{:__block__, do_meta, [:do]}, {:__block__, block_meta, new_stmts}}

              other ->
                other
            end)

          {:defmodule, mod_meta, [name, new_body_kw]}

        node ->
          node
      end)

    if result == ast do
      Sourceror.to_string(ast)
    else
      Sourceror.to_string(result)
    end
  end

  # Build the `@type t :: %__MODULE__{field: list(), ...}` AST node.
  defp build_type_attr(fields) do
    type_fields =
      Enum.map(fields, fn field ->
        {{:__block__, [format: :keyword], [field]}, {:list, [], []}}
      end)

    type_map = {:%, [], [{:__MODULE__, [], nil}, {:%{}, [], type_fields}]}
    type_spec = {:"::", [], [{:t, [], nil}, type_map]}
    {:@, [end_of_expression: [newlines: 2]], [{:type, [], [type_spec]}]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
