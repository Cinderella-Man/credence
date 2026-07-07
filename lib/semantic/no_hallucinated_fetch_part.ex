defmodule Credence.Semantic.NoHallucinatedFetchPart do
  @moduledoc """
  Repairs the LLM hallucination of `Plug.Conn.fetch_part/2` — a function that
  does not exist in any Plug version.

  LLMs frequently generate `Plug.Conn.fetch_part(conn, "file")` when
  implementing file-upload routers. The compiler emits a warning about
  `init/1` being `defp` instead of `def` (the module fails to compile as a
  proper Plug). The `UndefinedFunction` rule can fire but cannot fix the
  pattern; this rule provides the deterministic repair.

  The fix rewrites:

      case Plug.Conn.fetch_part(conn, "file") do
        {:ok, %{file: %Plug.Upload{} = upload}, _} -> ...
        _ -> ...
      end

  to the idiomatic:

      case conn.params["file"] do
        %Plug.Upload{} = upload -> ...
        _ -> ...
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "function init/1 required by behaviour Plug was implemented as \"defp\" but should have been \"def\""

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_fetch_part,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, _} =
        Macro.prewalk(ast, false, fn
          {:case, meta, [condition, clauses_block]} = node, false ->
            case find_fetch_part_call(condition) do
              nil ->
                {node, false}

              _fetch_part_call ->
                case transform_case(meta, condition, clauses_block) do
                  {:ok, transformed} -> {transformed, true}
                  :error -> {node, false}
                end
            end

          node, acc ->
            {node, acc}
        end)

      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  defp find_fetch_part_call({{:., _, [{:__aliases__, _, [:Plug, :Conn]}, :fetch_part]}, _, _} = node) do
    node
  end

  defp find_fetch_part_call({:case, _, [condition, _]}) do
    find_fetch_part_call(condition)
  end

  defp find_fetch_part_call(_), do: nil

  defp transform_case(meta, _condition, clauses_block) do
    new_condition = build_conn_params_access()

    case clauses_block do
      [{{:__block__, do_meta, [:do]}, clause_asts}] ->
        case transform_clauses(clause_asts) do
          {:ok, new_clauses} ->
            {:ok, {:case, meta, [new_condition, [{{:__block__, do_meta, [:do]}, new_clauses}]]}}

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  # Build AST for: conn.params["file"]
  defp build_conn_params_access do
    {{:., [],
      [
        {:conn, [], nil},
        :params
      ]},
     [no_parens: true], []}
    |> then(fn params_access ->
      {{:., [from_brackets: true],
        [
          Access,
          :get
        ]},
       [from_brackets: true],
       [
         params_access,
         {:__block__, [delimiter: "\""], ["file"]}
       ]}
    end)
  end

  defp transform_clauses(clauses) do
    case clauses do
      [
        {:->, arrow_meta1,
         [
           [match_pattern],
           body1
         ]},
        {:->, arrow_meta2,
         [
           [{:_, _, nil} = wildcard],
           body2
         ]}
      ] ->
        case extract_upload_var(match_pattern) do
          {:ok, upload_var} ->
            new_pattern = build_upload_pattern(upload_var)

            {:ok,
             [
               {:->, arrow_meta1, [[new_pattern], body1]},
               {:->, arrow_meta2, [[wildcard], body2]}
             ]}

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  # Extract the upload variable from: {:{}, _, [:ok, {:%{}, _, [file: {:=, _, [%Plug.Upload{}, var]}]}, _]}
  defp extract_upload_var(
         {:{}, _meta,
          [
            {:__block__, _, [:ok]},
            {:%{}, _, map_entries},
            {:_, _, nil}
          ]}
       ) do
    case map_entries do
      [{{:__block__, _, [:file]}, {:=, _, [_, {var_name, _, nil}]}}]
      when is_atom(var_name) ->
        {:ok, var_name}

      _ ->
        :error
    end
  end

  defp extract_upload_var(_), do: :error

  # Build: %Plug.Upload{} = upload_var
  defp build_upload_pattern(upload_var) do
    {:=, [],
     [
       {:%, [],
        [
          {:__aliases__, [trailing_comments: [], leading_comments: []], [:Plug, :Upload]},
          {:%{}, [], []}
        ]},
       {upload_var, [], nil}
     ]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
