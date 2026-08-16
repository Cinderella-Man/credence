defmodule Credence.Semantic.NoBareNamesInSpec do
  @moduledoc """
  Fixes compiler errors about undefined types caused by bare names in @spec.

  When an LLM generates a @spec with bare parameter names (e.g., `sub_list`)
  instead of properly annotated parameters (e.g., `sub_list :: any()`), the
  Elixir compiler interprets those bare names as type references and emits:

      type sub_list/0 undefined (no such type in Module)

  This rule detects that diagnostic and rewrites the bare name into an
  annotated parameter with `:: any()` so the spec compiles.

  ## Bad

      defmodule MyModNBNIS do
        @spec foo(my_param) :: integer()
        def foo(x), do: x
      end

  ## Good

      defmodule MyModNBNIS do
        @spec foo(my_param :: any()) :: integer()
        def foo(x), do: x
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(~r/type \w+\/0 undefined/, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_bare_names_in_spec,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    bare_name = extract_bare_name(diagnostic.message)

    case bare_name do
      nil ->
        source

      name ->
        result = fix_bare_name(source, name, line(diagnostic))
        # Preserve trailing newline if source had one
        if String.ends_with?(source, "\n") and not String.ends_with?(result, "\n") do
          result <> "\n"
        else
          result
        end
    end
  end

  defp extract_bare_name(message) do
    case Regex.run(~r/type (\w+)\/0 undefined/, message) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp fix_bare_name(source, bare_name, target_line) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        bare_atom = String.to_atom(bare_name)

        transformed =
          Macro.prewalk(ast, fn
            # Match a bare name in @spec args: {:@, _, [{:spec, _, [{:"::", _, [func_call, return_type]}]}]}
            # Inside func_call args, bare names have shape {:name, meta, nil}.
            #
            # Only the `@spec` on the diagnostic's own line is rewritten.
            # The compiler error names a type, not a line-spanning shape, so a
            # bare name like `sub_list` may be a genuine, defined type used as a
            # spec arg in *another* module/spec in the same source — there the
            # `foo(sub_list)` spec is valid and means "arg of type sub_list".
            # Rewriting every spec by name would widen that valid spec to
            # `:: any()`, changing its meaning. Targeting the diagnostic line
            # keeps the fix to the one spec the compiler actually rejected.
            {:@, meta, [{:spec, spec_meta, [spec_body]}]} = node ->
              if Keyword.get(meta, :line) == target_line do
                fixed_body = fix_spec_body(spec_body, bare_atom)
                {:@, meta, [{:spec, spec_meta, [fixed_body]}]}
              else
                node
              end

            node ->
              node
          end)

        Sourceror.to_string(transformed)

      {:error, _} ->
        source
    end
  end

  # `@spec f(...) :: ret when t: var` — unwrap the guard and fix the spec inside it.
  # The guards themselves are left alone: they bind type variables, and annotating
  # a binding would change what the spec means rather than repair it.
  #
  # Without this clause the catch-all below returned the body untouched, so a spec
  # carrying a `when` was a no-op even for a *top-level* bare argument — a shape
  # outside the boundary the escalation ledger recorded for row 90.
  defp fix_spec_body({:when, meta, [body, guards]} = node, bare_atom) do
    # A name the guard BINDS is a type variable, not an undefined type — and
    # annotating it does not compile: `@spec parse(t :: any()) :: map when t: atom()`
    # both names the argument `t` and binds `t`, which Elixir rejects. Decline and
    # leave the compile error, which at least names the file and line.
    #
    # Found by asserting `compiles?/1` rather than the output text; the text-only
    # version of this test passed on source the compiler refuses.
    if bare_atom in guard_bound(guards) do
      node
    else
      {:when, meta, [fix_spec_body(body, bare_atom), guards]}
    end
  end

  defp fix_spec_body({:"::", meta, [func_args, return_type]}, bare_atom) do
    {:"::", meta, [fix_func_args(func_args, bare_atom), annotate(return_type, bare_atom)]}
  end

  defp fix_spec_body(other, _bare_atom), do: other

  # The type variables a spec's `when` clause binds. Sourceror renders the guard
  # as a keyword list (`when t: atom()`), sometimes wrapped in a `:__block__`.
  defp guard_bound(guards) when is_list(guards) do
    Enum.flat_map(guards, fn
      {{:__block__, _, [name]}, _type} when is_atom(name) -> [name]
      {name, _type} when is_atom(name) -> [name]
      _ -> []
    end)
  end

  defp guard_bound({:__block__, _, [inner]}), do: guard_bound(inner)
  defp guard_bound(_), do: []

  # Only the ARGUMENTS are walked, never the function-name position: `@spec
  # sub_list(sub_list) :: map` must not become `(sub_list :: any())(...)`.
  defp fix_func_args({func_name, meta, args}, bare_atom) when is_list(args) do
    {func_name, meta, Enum.map(args, &annotate(&1, bare_atom))}
  end

  defp fix_func_args(other, _bare_atom), do: other

  # Annotate every occurrence of the undefined name *anywhere inside a type term*,
  # not just as a direct argument.
  #
  # The old `fix_arg/2` matched only a top-level element of the argument list, so
  # the rule claimed the diagnostic and then returned byte-identical source for
  # every nested position — inside a `|` union, a list or tuple type, or the return
  # type (escalation ledger rows 90 and 65, reproduced). That is the worst shape a
  # Semantic rule can have: `lib/semantic.ex` records `{rule, 1}` even for a no-op
  # and dispatches with `Enum.find`, so the rule consumed the diagnostic, no other
  # rule could claim it, and the compile error survived every pass.
  #
  # Annotating in place rather than substituting a bare `any()` keeps the name the
  # author wrote, which is the whole value of a named spec argument — and it is
  # what this rule already did at the top level, so the two positions now agree.
  # Verified that `name :: any()` compiles in argument, union, list, tuple and
  # return positions.
  defp annotate({:"::", meta, [lhs, rhs]}, bare_atom) do
    # A `::` left side is already a name, so it is not a type reference to repair.
    {:"::", meta, [lhs, annotate(rhs, bare_atom)]}
  end

  defp annotate({name, meta, nil}, bare_atom) when name == bare_atom do
    pos = [line: meta[:line] || 0, column: meta[:column] || 0]
    {:"::", pos, [{name, meta, nil}, {:any, pos, []}]}
  end

  defp annotate({form, meta, args}, bare_atom) when is_list(args) do
    # `form` is left as-is: when it is an atom this is a call — a *parameterised*
    # type like `sub_list(t)` — and a parameterised type is not the bare `name/0`
    # the compiler reported.
    {form, meta, Enum.map(args, &annotate(&1, bare_atom))}
  end

  defp annotate({a, b}, bare_atom), do: {annotate(a, bare_atom), annotate(b, bare_atom)}

  defp annotate(list, bare_atom) when is_list(list),
    do: Enum.map(list, &annotate(&1, bare_atom))

  defp annotate(other, _bare_atom), do: other

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
