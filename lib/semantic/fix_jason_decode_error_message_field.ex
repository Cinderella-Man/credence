defmodule Credence.Semantic.FixJasonDecodeErrorMessageField do
  @moduledoc """
  Fixes compile errors caused by LLMs pattern-matching `%Jason.DecodeError{message: msg}`
  when `:message` is not a field on `Jason.DecodeError` (only `:position`, `:token`
  and `:data` exist).

  The compiler emits:

      "unknown key :message for struct Jason.DecodeError"

  The fix keeps the struct match (so the clause still selects only
  `Jason.DecodeError` values), binds the whole exception, and uses
  `Exception.message/1` at every use site in the clause body:

      # Before (compile error):
      {:error, %Jason.DecodeError{message: msg}} -> "Invalid JSON: \#{msg}"

      # After (compiles correctly):
      {:error, %Jason.DecodeError{} = error} -> "Invalid JSON: \#{Exception.message(error)}"

  The rewrite is deliberately narrow — a clause is left untouched (the fix is a
  no-op) whenever the substitution could change meaning or produce invalid code:

    * the struct pattern has entries besides `message:` (their bindings would
      be lost);
    * the `message:` value is not a plain variable (literal, pin, nested
      pattern — matching on a specific message cannot be preserved);
    * the variable appears in the clause guard (`Exception.message/1` is not
      allowed in guards);
    * the variable appears elsewhere in the clause pattern (an equality
      constraint the rewrite cannot express);
    * the variable is rebound inside the body (`msg = ...`, `fn msg -> ...`,
      `msg <- ...`) — substituting a call into a pattern position would not
      compile;
    * a variable named `error` is already in use in the clause (the new
      binding would capture it).

  ## Bad

      defmodule M do
        def f(x, list) do
          case Jason.decode(x) do
            {:error, %Jason.DecodeError{message: msg}} -> Enum.map(list, fn msg -> msg end)
          end
        end
      end

  ## Good

      defmodule M do
        def f(x, list) do
          case Jason.decode(x) do
            {:error, %Jason.DecodeError{}} -> Enum.map(list, fn msg -> msg end)
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key :message for struct Jason.DecodeError"

  @new_var :error

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_jason_decode_error_message_field,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:->, clause_meta, [patterns, body]}, acc ->
            case find_and_fix_clause(patterns, body) do
              {:ok, new_patterns, new_body} ->
                {{:->, clause_meta, [new_patterns, new_body]}, true}

              :error ->
                {{:->, clause_meta, [patterns, body]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp find_and_fix_clause(patterns, body) do
    {pats, guard} = split_guard(patterns)

    with [{:var, var_name}] <- message_struct_vars(pats),
         true <- safe_to_rewrite?(pats, guard, body, var_name) do
      bind? = count_var(body, var_name) > 0
      new_pats = rewrite_struct(pats, bind?)
      new_patterns = rejoin_guard(patterns, new_pats, guard)
      new_body = if bind?, do: replace_var_in_body(body, var_name), else: body
      {:ok, new_patterns, new_body}
    else
      _ -> :error
    end
  end

  # A clause's patterns are `[{:when, _, [pat1, ..., patN, guard]}]` when guarded.
  defp split_guard([{:when, _, when_args}]) when is_list(when_args) do
    {Enum.drop(when_args, -1), List.last(when_args)}
  end

  defp split_guard(patterns), do: {patterns, nil}

  defp rejoin_guard([{:when, meta, _}], new_pats, guard),
    do: [{:when, meta, new_pats ++ [guard]}]

  defp rejoin_guard(_patterns, new_pats, _guard), do: new_pats

  defp safe_to_rewrite?(pats, guard, body, var_name) do
    # The message var must occur exactly once in the pattern (inside the
    # struct) and never in the guard; it must not be rebound in the body;
    # and the fresh `error` binding must not capture an existing variable.
    count_var(pats, var_name) == 1 and
      (guard == nil or count_var(guard, var_name) == 0) and
      not var_rebound_in_body?(body, var_name) and
      (var_name == @new_var or
         count_var([pats, guard, body], @new_var) == 0)
  end

  # Variables bound by `%Jason.DecodeError{message: <plain var>}` patterns,
  # for structs whose ONLY entry is `message:`. Structs with extra entries or
  # a non-var message value yield `:unsafe`, poisoning the match in
  # `find_and_fix_clause` (it requires exactly `[{:var, var_name}]`).
  defp message_struct_vars(pats) do
    {_, found} =
      Macro.prewalk(pats, [], fn
        {:%, _, [{:__aliases__, _, [:Jason, :DecodeError]}, {:%{}, _, entries}]} = node, acc ->
          case classify_entries(entries) do
            nil -> {node, acc}
            result -> {node, [result | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp classify_entries(entries) do
    case find_message_entry(entries) do
      nil -> nil
      {:var, var_name} when length(entries) == 1 -> {:var, var_name}
      _ -> :unsafe
    end
  end

  # nil (no `message:` key), {:var, name} (plain-variable value), or :unsafe.
  defp find_message_entry(entries) when is_list(entries) do
    Enum.find_value(entries, fn
      {{:__block__, _, [:message]}, value} ->
        case value do
          {var_name, _meta, nil} when is_atom(var_name) -> {:var, var_name}
          _ -> :unsafe
        end

      _ ->
        nil
    end)
  end

  defp find_message_entry(_), do: nil

  defp count_var(ast, var_name) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {^var_name, _, nil} = node, acc -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end

  # True when the var appears in any binding position inside the body:
  # `=` left side, `->` clause patterns (incl. their guards), `<-` left side.
  # Over-approximates (a use in a nested guard counts too) — over-skipping
  # only makes the fix a no-op, never wrong.
  defp var_rebound_in_body?(body, var_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:=, _, [lhs, _rhs]} = node, acc -> {node, acc or count_var(lhs, var_name) > 0}
        {:->, _, [pats, _body]} = node, acc -> {node, acc or count_var(pats, var_name) > 0}
        {:<-, _, [lhs, _rhs]} = node, acc -> {node, acc or count_var(lhs, var_name) > 0}
        node, acc -> {node, acc}
      end)

    found
  end

  defp rewrite_struct(pats, bind?) do
    Macro.prewalk(pats, fn
      {:%, meta,
       [{:__aliases__, _, [:Jason, :DecodeError]} = alias_node, {:%{}, map_meta, entries}]} = node ->
        if find_message_entry(entries) do
          bare = {:%, meta, [alias_node, {:%{}, map_meta, []}]}
          if bind?, do: {:=, [], [bare, {@new_var, [], nil}]}, else: bare
        else
          node
        end

      node ->
        node
    end)
  end

  # Postwalk, not prewalk: the replacement node itself contains an `error`
  # var, so a prewalk would re-match it forever when the message var is
  # already named `error`.
  defp replace_var_in_body(body, var_name) do
    Macro.postwalk(body, fn
      {^var_name, meta, nil} ->
        {{:., [], [{:__aliases__, [], [:Exception]}, :message]}, [], [{@new_var, meta, nil}]}

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
