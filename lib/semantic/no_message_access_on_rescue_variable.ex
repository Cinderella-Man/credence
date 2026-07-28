defmodule Credence.Semantic.NoMessageAccessOnRescueVariable do
  @moduledoc """
  Fixes the compiler warning caused by accessing `.message` on a bare-rescue
  variable.

  LLMs frequently write `rescue e -> e.message` but Elixir's type system warns
  that a bare-rescue variable has unknown struct fields; the `.message` access
  triggers "unknown key .message" which fails `--warnings-as-errors`.

  The deterministic fix is `Exception.message(e)`:

      rescue e -> {:error, e.message}                 # WRONG — warns
      rescue e -> {:error, Exception.message(e)}      # correct
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key .message"
  # The compiler emits this hint only for the `:anonymous_rescue` type check,
  # i.e. a bare `rescue e ->`. Requiring it keeps `match?` from firing on
  # unrelated "unknown key .message" warnings (e.g. a typed map missing the
  # key), which the structural fix would leave untouched anyway — so check and
  # fix agree on exactly the bare-rescue case.
  @rescue_hint "rescue without specifying exception names"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, @rescue_hint)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_message_access_on_rescue_variable,
      message: "accessing .message on a bare-rescue variable is unsafe; use Exception.message/1",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          # Only rewrite inside a `rescue` block's clauses. The compiler warns
          # exclusively for the bare-rescue variable; rewriting every `.message`
          # in the file would break valid access on a struct/map that really
          # does have a `:message` field (turning `w.message` into
          # `Exception.message(w)`, which raises on a non-exception).
          {rescue_key, clauses} = node when is_list(clauses) ->
            if rescue_key?(rescue_key) do
              {rescue_key, Enum.map(clauses, &rewrite_clause/1)}
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

  # Sourceror renders the `rescue:` keyword as a `__block__`-wrapped atom; the
  # plain atom form is handled too for robustness.
  defp rescue_key?({:__block__, _, [:rescue]}), do: true
  defp rescue_key?(:rescue), do: true
  defp rescue_key?(_), do: false

  # A bare-rescue clause binds a single plain variable (`rescue e ->`). Only
  # then is the variable guaranteed to be an exception, so `Exception.message/1`
  # is a safe substitute for `e.message`. Typed (`e in RuntimeError`) and struct
  # patterns don't warn and are left alone. If the variable is rebound in the
  # body it may no longer be an exception, so the clause is left untouched.
  defp rewrite_clause({:->, meta, [[{var, _, ctx}] = pattern, body]})
       when is_atom(var) and is_atom(ctx) and var != :_ do
    if var_rebound_in_body?(body, var) do
      {:->, meta, [pattern, body]}
    else
      {:->, meta, [pattern, replace_message_access(body, var)]}
    end
  end

  defp rewrite_clause(other), do: other

  defp replace_message_access(body, var) do
    Macro.prewalk(body, fn
      {{:., meta_dot, [{^var, var_meta, var_ctx}, :message]}, meta_call, []}
      when is_atom(var_ctx) ->
        {{:., meta_dot, [{:__aliases__, [line: meta_dot[:line] || 0], [:Exception]}, :message]},
         meta_call, [{var, var_meta, var_ctx}]}

      other ->
        other
    end)
  end

  # True when `var` appears in any binding position in the body (`=` LHS, `->`
  # or `<-` patterns) — an over-approximation that only ever makes the fix a
  # no-op, never wrong.
  defp var_rebound_in_body?(body, var) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:=, _, [lhs, _rhs]} = node, acc -> {node, acc or count_var(lhs, var) > 0}
        {:->, _, [pats, _body]} = node, acc -> {node, acc or count_var(pats, var) > 0}
        {:<-, _, [lhs, _rhs]} = node, acc -> {node, acc or count_var(lhs, var) > 0}
        node, acc -> {node, acc}
      end)

    found
  end

  defp count_var(ast, var) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {^var, _, ctx} = node, acc when is_atom(ctx) -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
