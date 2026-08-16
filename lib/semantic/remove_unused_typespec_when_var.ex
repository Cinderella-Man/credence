defmodule Credence.Semantic.RemoveUnusedTypespecWhenVar do
  @moduledoc """
  Fixes compiler errors caused by unused type variables in @spec clauses.

  When an LLM generates a typespec with a `when` clause that defines a type
  variable (e.g., `when var_ok: true`) but that variable is referenced only
  once (in the `when` clause itself), the Elixir compiler rejects it:

      type variable var_ok is used only once. Type variables in typespecs
      must be referenced at least twice, otherwise it is equivalent to term()

  Because the compiler counts the `when` binding as the variable's *only* use,
  the named variable is guaranteed not to appear in the spec's args or return
  type. The fix therefore removes only the offending binding from the `when`
  clause, leaving every other binding (and the spec itself) untouched:

      # Before (compiler error)
      @spec foo(x) :: x when x: integer, var_ok: true

      # After (compiles cleanly, `x` constraint preserved)
      @spec foo(x) :: x when x: integer

  When the offending binding is the only one in the `when` clause, the whole
  clause is dropped:

      # Before
      @spec foo(integer) :: integer when var_ok: true

      # After
      @spec foo(integer) :: integer

  ## Bad

      defmodule SolutionRUTWV do
        @spec foo(x) :: x when x: integer, var_ok: true
        def foo(x), do: x
      end

  ## Good

      defmodule SolutionRUTWV do
        @spec foo(x) :: x when x: integer
        def foo(x), do: x
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "type variable") and
      String.contains?(msg, "used only once")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :remove_unused_typespec_when_var,
      message: "Unused type variable in @spec — removing when clause binding",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: message} = diagnostic) do
    with name when not is_nil(name) <- extract_var_name(message),
         {:ok, ast} <- Sourceror.parse_string(source) do
      target_line = line(diagnostic)
      var_atom = String.to_atom(name)

      transformed =
        Macro.prewalk(ast, fn
          {:@, meta, [{:spec, spec_meta, [{:when, when_meta, [inner, bindings]}]}]} = node ->
            if Keyword.get(meta, :line) == target_line and is_list(bindings) do
              drop_binding(node, meta, spec_meta, when_meta, inner, bindings, var_atom)
            else
              node
            end

          node ->
            node
        end)

      result = Sourceror.to_string(transformed)

      # Preserve a trailing newline if the source had one.
      if String.ends_with?(source, "\n") and not String.ends_with?(result, "\n") do
        result <> "\n"
      else
        result
      end
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  defp drop_binding(node, meta, spec_meta, when_meta, inner, bindings, var_atom) do
    remaining = Enum.reject(bindings, fn pair -> binding_key(pair) == var_atom end)

    cond do
      # The named binding wasn't found on this line — leave the node alone.
      remaining == bindings ->
        node

      # No bindings left — drop the whole `when` clause.
      remaining == [] ->
        {:@, meta, [{:spec, spec_meta, [inner]}]}

      # Keep the other bindings.
      true ->
        {:@, meta, [{:spec, spec_meta, [{:when, when_meta, [inner, remaining]}]}]}
    end
  end

  defp binding_key({{:__block__, _, [key]}, _value}) when is_atom(key), do: key
  defp binding_key({key, _value}) when is_atom(key), do: key
  defp binding_key(_), do: nil

  defp extract_var_name(message) do
    case Regex.run(~r/type variable (\w+) is used only once/, message) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
