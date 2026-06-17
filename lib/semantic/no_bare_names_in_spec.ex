defmodule Credence.Semantic.NoBareNamesInSpec do
  @moduledoc """
  Fixes compiler errors about undefined types caused by bare names in @spec.

  When an LLM generates a @spec with bare parameter names (e.g., `sub_list`)
  instead of properly annotated parameters (e.g., `sub_list :: any()`), the
  Elixir compiler interprets those bare names as type references and emits:

      type sub_list/0 undefined (no such type in Module)

  This rule detects that diagnostic and rewrites the bare name into an
  annotated parameter with `:: any()` so the spec compiles.
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

  defp fix_spec_body({:"::", meta, [func_args, return_type]}, bare_atom) do
    fixed_func_args = fix_func_args(func_args, bare_atom)
    {:"::", meta, [fixed_func_args, return_type]}
  end

  defp fix_spec_body(other, _bare_atom), do: other

  defp fix_func_args({func_name, meta, args}, bare_atom) when is_list(args) do
    fixed_args = Enum.map(args, &fix_arg(&1, bare_atom))
    {func_name, meta, fixed_args}
  end

  defp fix_func_args(other, _bare_atom), do: other

  # A bare name has nil as the third element
  defp fix_arg({name, meta, nil} = node, bare_atom) do
    if name == bare_atom do
      # Replace with name :: any()
      {:"::", [line: meta[:line] || 0, column: meta[:column] || 0],
       [{name, meta, nil}, {:any, [line: meta[:line] || 0, column: meta[:column] || 0], []}]}
    else
      node
    end
  end

  defp fix_arg(other, _bare_atom), do: other

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
