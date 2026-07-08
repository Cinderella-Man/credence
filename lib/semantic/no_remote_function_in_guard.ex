defmodule Credence.Semantic.NoRemoteFunctionInGuard do
  @moduledoc """
  Fixes `cannot invoke remote function ... inside a guard` compile errors.

  LLMs repeatedly place non-guard-safe remote functions (e.g.
  `System.monotonic_time/1`, `DateTime.utc_now/0`) in `when` guard clauses.
  The Elixir compiler rejects this with:

      "cannot invoke remote function System.monotonic_time/1 inside a guard"

  The deterministic fix extracts the guarded `defp` clause's condition into an
  `if` inside the function body and merges any same-name/arity fallback clause
  into the `else` branch, eliminating the guard entirely.

  ## Before

      defp loop(start_time, timeout)
           when System.monotonic_time(:millisecond) - start_time >= timeout do
        :timeout
      end

      defp loop(start_time, timeout) do
        Process.sleep(10)
        loop(start_time, timeout)
      end

  ## After

      defp loop(start_time, timeout) do
        if System.monotonic_time(:millisecond) - start_time >= timeout do
          :timeout
        else
          Process.sleep(10)
          loop(start_time, timeout)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "cannot invoke remote function "

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and String.ends_with?(msg, " inside a guard")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_remote_function_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, module, function} <- extract_remote_fn(diagnostic.message) do
      fn_alias = {:__aliases__, [], [module]}
      fn_capture = {:., [], [fn_alias, function]}
      diag_line = line(diagnostic)

      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:__block__, meta, stmts} = node, acc ->
            case transform_stmts(stmts, fn_capture, diag_line) do
              {:ok, new_stmts} -> {{:__block__, meta, new_stmts}, true}
              :error -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Extract the module and function atoms from the diagnostic message.
  # "cannot invoke remote function System.monotonic_time/1 inside a guard"
  # => {:System, :monotonic_time}
  defp extract_remote_fn(msg) do
    case Regex.run(~r/cannot invoke remote function (\w+(?:\.\w+)*)\.(\w+)\/\d+ inside a guard/, msg) do
      [_, mod_str, fun_str] ->
        module = mod_str |> String.split(".") |> Enum.map(&String.to_atom/1) |> List.last()
        {:ok, module, String.to_atom(fun_str)}

      _ ->
        :error
    end
  end

  # Try to transform a list of sibling statements (def/defp clauses).
  defp transform_stmts(stmts, fn_capture, diag_line) do
    case do_transform(stmts, fn_capture, diag_line) do
      {:ok, new_stmts} -> {:ok, new_stmts}
      :error -> :error
    end
  end

  defp do_transform([], _fn_capture, _diag_line), do: :error

  defp do_transform([stmt | rest], fn_capture, diag_line) do
    case try_merge(stmt, rest, fn_capture, diag_line) do
      {:ok, merged, remaining} ->
        {:ok, [merged | remaining]}

      :error ->
        case do_transform(rest, fn_capture, diag_line) do
          {:ok, new_rest} -> {:ok, [stmt | new_rest]}
          :error -> :error
        end
    end
  end

  # Try to merge `clause` (a guarded def/defp) with a matching fallback clause.
  defp try_merge({kind, meta, [{:when, when_meta, [fn_head, guard]}, body_kw]}, rest, fn_capture, diag_line)
       when kind in [:def, :defp] do
    unless guard_contains?(guard, fn_capture) and on_line?(when_meta, diag_line) do
      throw(:no_match)
    end

    {name, arity} = fn_name_arity(fn_head)

    case pop_fallback(rest, kind, name, arity) do
      {:ok, fallback_body, remaining} ->
        merged = build_merged(kind, meta, fn_head, guard, body_kw, fallback_body)
        {:ok, merged, remaining}

      :error ->
        throw(:no_match)
    end
  catch
    :no_match -> :error
  end

  defp try_merge(_clause, _rest, _fn_capture, _diag_line), do: :error

  # Find and remove the first clause of `kind` with matching name/arity and no guard.
  defp pop_fallback([], _kind, _name, _arity), do: :error

  defp pop_fallback([{kind, clause_meta, [fn_head, body_kw]} | rest], kind, name, arity) do
    case fn_head do
      {^name, _, args} when is_list(args) and length(args) == arity ->
        {:ok, body_kw, rest}

      {:when, _, [{^name, _, args}, _guard]} when is_list(args) and length(args) == arity ->
        case pop_fallback(rest, kind, name, arity) do
          {:ok, fallback_body, remaining} ->
            {:ok, fallback_body, [{kind, clause_meta, [fn_head, body_kw]} | remaining]}
          :error -> :error
        end

      _ ->
        case pop_fallback(rest, kind, name, arity) do
          {:ok, fallback_body, remaining} ->
            {:ok, fallback_body, [{kind, clause_meta, [fn_head, body_kw]} | remaining]}
          :error -> :error
        end
    end
  end

  defp pop_fallback([other | rest], kind, name, arity) do
    case pop_fallback(rest, kind, name, arity) do
      {:ok, fallback_body, remaining} -> {:ok, fallback_body, [other | remaining]}
      :error -> :error
    end
  end

  # Build the merged clause: defp head with body as `if guard do original else fallback end`
  # We borrow :do/:end metadata from the defp clause so Sourceror renders block-style.
  defp build_merged(kind, meta, fn_head, guard, body_kw, fallback_body_kw) do
    original_body = extract_do(body_kw)
    fallback_body = extract_do(fallback_body_kw)

    # Sourceror needs :do and :end on the :if node to emit block layout.
    if_meta =
      meta
      |> Keyword.take([:do, :end, :line, :column])

    if_node =
      {:if, if_meta,
       [
         guard,
         [
           {{:__block__, [], [:do]}, original_body},
           {{:__block__, [], [:else]}, fallback_body}
         ]
       ]}

    clean_head = strip_when(fn_head)
    new_body = [{{:__block__, [], [:do]}, if_node}]
    {kind, meta, [clean_head, new_body]}
  end

  # Extract the body from a Sourceror keyword list [{{:__block__, _, [:do]}, body}]
  defp extract_do([{{:__block__, _, [:do]}, body} | _]), do: body
  defp extract_do(body), do: body

  # Strip the `when` from a function head: {:when, _, [actual_head, _guard]} -> actual_head
  defp strip_when({:when, _, [head, _guard]}), do: head
  defp strip_when(head), do: head

  # Get {name, arity} from a function head
  defp fn_name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp fn_name_arity({:when, _, [{name, _, args}, _]}) when is_list(args), do: {name, length(args)}

  # Check if a guard expression contains the given remote function call.
  # fn_capture is {:., [], [{:__aliases__, [], [Module]}, :function]}.
  # We compare metadata-insensitively: strip metadata from the AST dot node.
  defp guard_contains?(guard, {_, _, [{:__aliases__, _, [mod]}, fun]}) do
    {_guard, found} =
      Macro.prewalk(guard, false, fn
        {{:., _, [{:__aliases__, _, [ast_mod]}, ast_fun]}, _meta, _args} = node, _acc ->
          {node, ast_mod == mod and ast_fun == fun}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Check if a node's metadata line matches the diagnostic line
  defp on_line?(meta, diag_line) when is_list(meta) do
    Keyword.get(meta, :line) == diag_line
  end

  defp on_line?(_, _), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
