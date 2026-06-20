defmodule Credence.Pattern.PreferNoQuestionMarkForNonBoolean do
  @moduledoc """
  Detects functions with a `?` suffix whose `@spec` declares a non-boolean
  return type and renames them to drop the suffix.

  In Elixir, the `?` suffix conventionally indicates a boolean predicate
  (returns `true` or `false`). A function with a `@spec` returning
  `integer() | nil`, `String.t()`, or any other non-boolean type should
  not use the `?` suffix.

  Only **private** (`defp`) functions are flagged. Renaming a public `def` is a
  breaking API change for callers in other modules, and the rename can't reach
  `@doc`/`c:Mod.fun?/n` references outside the analysed AST; a `?` on a public
  function is also often a deliberate mirror of a wrapped boolean API. So the
  rule cleans up only private helpers, whose every call site lives in-module.

  ## Bad

      @spec find_max_integer?([any()]) :: integer() | nil
      defp find_max_integer?([]), do: nil
      defp find_max_integer?(list) when is_list(list) do
        if Enum.any?(list, fn element -> not is_integer(element) end) do
          nil
        else
          Enum.max(list)
        end
      end

  ## Good

      @spec find_max_integer([any()]) :: integer() | nil
      defp find_max_integer([]), do: nil
      defp find_max_integer(list) when is_list(list) do
        if Enum.any?(list, fn element -> not is_integer(element) end) do
          nil
        else
          Enum.max(list)
        end
      end

  ## Auto-fix

  Renames all occurrences of the flagged private function (in `@spec`, `defp`,
  and in-module call sites) to the name without the `?` suffix.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    flagged_names = collect_flagged_names(ast)

    Enum.map(flagged_names, fn {name, line} ->
      %Issue{
        rule: :prefer_no_question_mark_for_non_boolean,
        message:
          "Function `#{name}?/...` has a `?` suffix but its @spec declares a non-boolean " <>
            "return type. Rename to `#{name}/...` to follow Elixir naming conventions.",
        meta: %{line: line}
      }
    end)
  end

  @impl true
  def fix_patches(ast, _opts) do
    flagged_names = collect_flagged_names(ast)

    if flagged_names == [] do
      []
    else
      # Build a set of names to rename (with the ? suffix)
      names_to_rename =
        MapSet.new(flagged_names, fn {name, _line} -> :"#{name}?" end)

      Credence.RuleHelpers.patches_from_postwalk(ast, fn
        {name, meta, ctx} = node when is_atom(name) ->
          if MapSet.member?(names_to_rename, name) do
            # Remove the ? suffix
            clean_name = name |> Atom.to_string() |> String.trim_trailing("?") |> String.to_atom()
            {clean_name, meta, ctx}
          else
            node
          end

        node ->
          node
      end)
    end
  end

  # Collect function names from @spec attributes that end with ? and have
  # a non-boolean return type.
  #
  # Restricted to *private* (`defp`) functions: renaming a public `def` is a
  # breaking API change for callers in other modules, and the rename also can't
  # reach `@doc`/`c:Mod.fun?/n` references outside this AST. A `?` on a public
  # function is often a deliberate mirror of a wrapped boolean API (e.g.
  # `Ecto.Multi.exists?` mirroring `Repo.exists?`), so we leave public names
  # alone and only clean up private helpers whose callers all live in-module.
  defp collect_flagged_names(ast) do
    private = private_only_names(ast)
    defined = all_defined_names(ast)

    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {:@, _meta, [{:spec, spec_meta, [spec_body]}]} = node, acc ->
          case extract_spec_info(spec_body) do
            {:ok, name, return_type} ->
              clean_name =
                name |> Atom.to_string() |> String.trim_trailing("?") |> String.to_atom()

              # Skip when the de-suffixed name already names a function (any
              # arity) in the AST. The fix renames by name across all arities,
              # so `foo?` -> `foo` would collide with an existing `foo`, merging
              # clauses and changing which body runs. `valid?`/`valid`,
              # `count?`/`count` etc. make this collision common, so we only
              # rename when the target name is free.
              if String.ends_with?(Atom.to_string(name), "?") and
                   not boolean_type?(return_type) and
                   MapSet.member?(private, name) and
                   not MapSet.member?(defined, clean_name) do
                line = Keyword.get(spec_meta, :line)
                {node, [{clean_name, line} | acc]}
              else
                {node, acc}
              end

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(names)
  end

  # Names defined by `defp` and NOT also by `def`. A name with any public clause
  # is treated as public (and skipped), since the rename would still break that
  # public arity.
  defp private_only_names(ast) do
    {_ast, {public, private}} =
      Macro.prewalk(ast, {MapSet.new(), MapSet.new()}, fn
        {:def, _, [head | _]} = node, {pub, priv} ->
          {node, {put_fun_name(pub, head), priv}}

        {:defp, _, [head | _]} = node, {pub, priv} ->
          {node, {pub, put_fun_name(priv, head)}}

        node, acc ->
          {node, acc}
      end)

    MapSet.difference(private, public)
  end

  # Every function name (def or defp, any arity) defined anywhere in the AST.
  # Used as the collision set for the de-suffixed rename target.
  defp all_defined_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {def_type, _, [head | _]} = node, acc when def_type in [:def, :defp] ->
          {node, put_fun_name(acc, head)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp put_fun_name(set, head) do
    case fun_name(head) do
      nil -> set
      name -> MapSet.put(set, name)
    end
  end

  defp fun_name({:when, _, [inner | _]}), do: fun_name(inner)
  defp fun_name({name, _, _}) when is_atom(name), do: name
  defp fun_name(_), do: nil

  # Extract function name and return type from a spec body.
  # spec_body is typically {:"::", meta, [fun_spec, return_type]}
  defp extract_spec_info({:"::", _meta, [fun_spec, return_type]}) do
    case fun_spec do
      {name, _meta, _args} when is_atom(name) ->
        {:ok, name, return_type}

      _ ->
        :error
    end
  end

  defp extract_spec_info(_), do: :error

  # Check if a type AST represents a boolean type.
  # boolean() -> {:boolean, [], []}
  # true | false -> {:|, _, [{:__block__, _, [true]}, {:__block__, _, [false]}]} or similar
  defp boolean_type?({:boolean, _, _}), do: true

  # `bool()` is the (deprecated) Erlang alias for `boolean()` — a function spec'd
  # `:: bool()` is a genuine predicate and must not be stripped of its `?`.
  defp boolean_type?({:bool, _, _}), do: true

  defp boolean_type?({:|, _, [left, right]}) do
    # Check if it's a union of true | false
    simple_union_boolean?([left, right])
  end

  defp boolean_type?(_), do: false

  # Check if a list of types is exactly [true, false] or [false, true]
  # Handles both bare atoms and {:__block__, _, [value]} wrappers
  defp simple_union_boolean?(types) do
    values = Enum.map(types, &unwrap_block/1)
    sorted = Enum.sort(values)
    sorted == [false, true]
  end

  # Unwrap {:__block__, _, [value]} to value
  defp unwrap_block({:__block__, _, [value]}), do: value
  defp unwrap_block(other), do: other
end
