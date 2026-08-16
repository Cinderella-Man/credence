defmodule Credence.Semantic.FixWithElseBareValue do
  @moduledoc """
  Fixes bare values in `else` clauses of `with` expressions.

  LLMs commonly write `with ... else bare_value end` forgetting that `else`
  requires `pattern -> body` clauses. The compiler rejects this at
  `severity: :error`.

  The fix wraps each bare expression in `_ -> expr`, which matches any value
  and returns the original expression.

  ## The message it keys on, and the one it used to

  This rule was **dead on arrival** and shipped that way. It matched

      "expected -> clauses for :else in \"with\""

  which Elixir 1.20.2 does not emit. The message it actually emits is

      invalid "else" block in "with", it expects "pattern -> expr" clauses

  so `match?/1` never returned true, the fix never ran, and nothing noticed —
  the rule's own tests fed it a hand-written diagnostic map carrying the string
  the rule expected, so the rule and its tests agreed with each other about a
  message the compiler never produced. That is the G1 class in docs/22 Part I §2,
  and the T1 pipeline-witness gate is what caught it (docs/22 T3.8).

  Only the mismatch was wrong. The rewrite itself was correct the whole time and
  is unchanged: fed the diagnostic by hand it produced valid, compiling output.

  Both spellings are matched. Only the second is verified here, by compiling a
  fixture on the toolchain in the tree; the first is kept because this project
  supports `~> 1.17` and it is presumably what some earlier version said. Keeping
  it costs nothing — no other live rule claims either message.

  ## Bad (compiles with error)

      defmodule WithElseRealDiagnostic do
        def run(x) do
          with {:ok, val} <- x do
            val
          else
            :error
          end
        end
      end

  ## Good

      defmodule WithElseRealDiagnostic do
        def run(x) do
          with {:ok, val} <- x do
            val
          else
            _ -> :error
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Elixir 1.20.2's wording, verified by compiling a fixture, and the older one
  # this rule shipped with. See the moduledoc.
  @match_msgs [
    ~s(invalid "else" block in "with", it expects "pattern -> expr" clauses),
    ~s(expected -> clauses for :else in "with")
  ]

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Enum.any?(@match_msgs, &String.contains?(msg, &1))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_with_else_bare_value,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:with, with_meta, args} ->
            new_args = fix_else_in_with(args)
            {:with, with_meta, new_args}

          node ->
            node
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

  defp fix_else_in_with(args) do
    Enum.map(args, fn
      blocks when is_list(blocks) ->
        Enum.map(blocks, fn
          {{:__block__, meta, [:else]}, body} = entry ->
            if bare_value?(body) do
              wrapped = [{:->, [], [[{:_, [], nil}], body]}]
              {{:__block__, meta, [:else]}, wrapped}
            else
              entry
            end

          other ->
            other
        end)

      other ->
        other
    end)
  end

  defp bare_value?(body) when is_list(body) do
    not match?([{:->, _, _} | _], body)
  end

  defp bare_value?(_), do: true

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
