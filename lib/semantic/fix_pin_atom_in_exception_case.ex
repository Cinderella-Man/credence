defmodule Credence.Semantic.FixPinAtomInExceptionCase do
  @moduledoc """
  Fixes the common LLM mistake of pinning a module atom in a `case` pattern
  inside a `rescue` block.

  When a rescue clause binds the exception to a variable `e` and then
  pattern-matches with `case e do ^exception -> …`, the pin matches a module
  atom (e.g. `ArgumentError`) against the exception struct (`%ArgumentError{…}`).
  Because atoms and structs are different types, the clause never matches at
  runtime.

  The fix replaces the bare pin `^exception` with a struct pin
  `%^{exception}{}`, which correctly matches the exception's `__struct__` key
  against the pinned module atom.

  The compiler emits:

      the following clause will never match:
          ^exception
      because it attempts to match on the result of:
          e
      which has type:
          %{..., __exception__: true, __struct__: atom()}
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "the following clause will never match"
  @exception_indicator "__exception__: true"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, @exception_indicator)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_pin_atom_in_exception_case,
      message:
        "pinning a module atom against an exception struct never matches; " <>
          "use %{^var}{} to match the struct",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    target_line = elem(diagnostic.position, 0)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          # Match a case clause arrow whose pattern is a bare pin: ^var ->
          # Only transform when the clause is on the diagnostic line.
          {:"->", arrow_meta, [[{:"^", _, _}], _body]} = node ->
            if Keyword.get(arrow_meta, :line) == target_line do
              case node do
                {:"->", arrow_meta, [[{:"^", pin_meta, [{atom, _atom_meta, nil}]}], body]}
                when is_atom(atom) ->
                  new_pattern =
                    {:%, pin_meta,
                     [{:"^", pin_meta, [{atom, pin_meta, nil}]}, {:%{}, pin_meta, []}]}

                  {:"->", arrow_meta, [[new_pattern], body]}

                _ ->
                  node
              end
            else
              node
            end

          other ->
            other
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
