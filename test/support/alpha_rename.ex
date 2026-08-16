defmodule Credence.AlphaRename do
  @moduledoc """
  Consistent variable renaming, for the generality bar of docs/12 **C12** (Rule
  Standard requirement 7).

  A rule should fire on the *construct*, not on the variable names that happened
  to be in the snippet it was generated from. The dominant defect signature in
  the auto-generated bursts was over-fitting, and a matcher keyed to incidental
  names is dead weight: it survives every test the author wrote, because the
  author wrote the fixtures too, and then never fires on real code.

  Renaming a rule's own fixture is the cheapest way to ask. It is the same move
  as the self-corruption oracle — *find an input the author did not choose* —
  applied to naming rather than to byte scope.

  ## What is renamed, and what deliberately is not

  Only **variables**: a `{name, meta, context}` node whose name is a lowercase
  atom and whose context is an atom rather than an argument list. That last
  test is the whole difficulty — `{:foo, meta, nil}` is the variable `foo` and
  `{:foo, meta, []}` is the call `foo()`, and they differ only there.

  Left alone, because renaming them would change what the code *means* rather
  than what it is called:

    * `__MODULE__`, `__DIR__` and friends — special forms, not variables;
    * a bare `_` — the discard, whose whole content is that it has no name;
    * the leading underscore of `_foo` — it marks intent-to-ignore, and a rule
      about unused variables keys on exactly that. `_foo` renames to `_v1`.

  Module names, function names, atoms and operators are all untouched by
  construction: none of them parse to a variable node.
  """

  @reserved [:__MODULE__, :__DIR__, :__ENV__, :__CALLER__, :__STACKTRACE__, :__aliases__, :_]

  @doc """
  `source` with every variable consistently renamed to `v1`, `v2`, … in order of
  first appearance. Returns `:unchanged` when the source has no variables to
  rename, so a caller can tell "renaming proved nothing" from "renaming was
  survived".
  """
  @spec rename(String.t()) :: {:ok, String.t()} | :unchanged | :error
  def rename(source) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {renamed, map} when map_size(map) > 0 <- walk(ast) do
      {:ok, Sourceror.to_string(renamed)}
    else
      {_ast, map} when is_map(map) -> :unchanged
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp walk(ast) do
    skip = protected_names(ast)

    Macro.prewalk(ast, %{}, fn
      {name, meta, context} = node, acc when is_atom(name) and is_atom(context) ->
        if variable?(name) and name not in skip do
          {new_name, acc} = fresh(acc, name)
          {{new_name, meta, context}, acc}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)
  end

  # Names that parse as variables but are not: attribute references and the
  # names in definition heads.
  defp protected_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:@, _, [{name, _, _} | _]} = node, acc ->
          {node, MapSet.put(acc, name)}

        {def_kind, _, [{name, _, _} | _]} = node, acc
        when def_kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp] ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp variable?(name) when name in @reserved, do: false

  defp variable?(name) do
    str = Atom.to_string(name)
    trimmed = String.trim_leading(str, "_")

    trimmed != "" and String.match?(trimmed, ~r/^[a-z][A-Za-z0-9_]*[?!]?$/)
  end

  defp fresh(acc, name) do
    case Map.fetch(acc, name) do
      {:ok, existing} ->
        {existing, acc}

      :error ->
        underscores =
          String.length(Atom.to_string(name)) -
            String.length(String.trim_leading(Atom.to_string(name), "_"))

        new_name = String.to_atom(String.duplicate("_", underscores) <> "v#{map_size(acc) + 1}")
        {new_name, Map.put(acc, name, new_name)}
    end
  end

  @doc """
  `[{rule, [fixture]}]` for every rule that fires on a fixture and stops firing
  once its variables are renamed — i.e. every rule keyed to a *name* rather than
  a construct (docs/12 C12, Rule Standard requirement 7).

  Takes both the rule list and the fixture source as arguments so the controls
  can drive it against fabricated rules; a gate whose vacuity depends on real
  debt stops working when the debt reaches zero, and here it starts there.

  ## The baseline is the whole trick

  A rule is compared against the **reprinted** source, not the original.
  `rename/1` goes through `Sourceror.to_string/1`, and that normalises things on
  its own — `'abc'` comes back as `~c"abc"` — so a rule looking for the old
  spelling stops firing for a reason that has nothing to do with names. Without
  the baseline this reports `PreferSigilCharlist` as name-keyed, which it is not.
  Anything the printer alone would have broken is the printer's business.
  """
  @spec offenders([module()], (module() -> [String.t()])) :: [{module(), [String.t()]}]
  def offenders(rules \\ Credence.Pattern.default_rules(), candidates \\ &default_candidates/1) do
    rules
    |> Enum.map(fn rule -> {rule, name_keyed_fixtures(rule, candidates.(rule))} end)
    |> Enum.reject(fn {_rule, fixtures} -> fixtures == [] end)
  end

  @doc false
  def default_candidates(rule), do: Credence.PipelineWitness.candidates(rule)

  defp name_keyed_fixtures(rule, fixtures) do
    Enum.filter(fixtures, fn source ->
      with baseline when is_binary(baseline) <- reprint(source),
           true <- fires?(rule, baseline),
           {:ok, renamed} <- rename(source) do
        not fires?(rule, renamed)
      else
        _ -> false
      end
    end)
  end

  defp reprint(source) do
    Sourceror.to_string(Sourceror.parse_string!(source))
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp fires?(rule, source) do
    rule.check(Sourceror.parse_string!(source), source: source) != []
  rescue
    _ -> false
  catch
    _, _ -> false
  end
end
