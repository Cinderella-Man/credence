defmodule Credence.Pattern.PreferFunctionCapture do
  @moduledoc """
  Detects single-argument anonymous functions that simply delegate to a
  function call and rewrites them using the more concise function capture
  syntax (`&Module.function/1` or `&function/1`).

  ## Bad

      Enum.map(list, fn x -> String.upcase(x) end)
      Enum.map(list, fn x -> to_string(x) end)

  ## Good

      Enum.map(list, &String.upcase/1)
      Enum.map(list, &to_string/1)

  ## When NOT flagged

  This rule only flags anonymous functions with exactly one parameter whose
  body is a single function call that uses the parameter exactly once as the
  sole argument. More complex patterns are not rewritten:

      fn x -> x + 1 end                    # body is not a function call
      fn x -> Enum.map(x, x) end           # param used more than once
      fn x, y -> Enum.map(x, y) end        # more than one param
      fn x -> Enum.map(x, &(&1 + 1)) end   # extra arguments beyond the param
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:fn, meta, [{:->, _, [[param], body]}]} = node, issues ->
          case analyze_fn_body(param, body) do
            {:ok, _capture_info} ->
              {node, [create_issue(meta) | issues]}

            :error ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:fn, _meta, [{:->, _, [[param], body]}]} = node ->
        case analyze_fn_body(param, body) do
          {:ok, capture_info} -> build_capture(capture_info)
          :error -> node
        end

      node ->
        node
    end)
  end

  # Analyze the body of a single-argument fn to see if it's a simple
  # delegation to a function call with the parameter used exactly once.
  defp analyze_fn_body(param, body) do
    param_name = extract_var_name(param)

    case body do
      # Remote function call: Module.function(arg)
      {{:., _, [{:__aliases__, _, module_parts}, fun_name]}, _, args}
      when is_atom(fun_name) and is_list(args) ->
        case args do
          [{var_name, _, nil}] when var_name == param_name ->
            {:ok, %{type: :remote, module: module_parts, fun: fun_name, arity: 1}}

          _ ->
            :error
        end

      # Local function call: function(arg)
      {fun_name, _, args} when is_atom(fun_name) and is_list(args) ->
        case args do
          [{var_name, _, nil}] when var_name == param_name ->
            {:ok, %{type: :local, fun: fun_name, arity: 1}}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp extract_var_name({name, _, _}) when is_atom(name), do: name
  defp extract_var_name(_), do: nil

  # Build the AST for the function capture syntax
  defp build_capture(%{type: :remote, module: module_parts, fun: fun_name, arity: arity}) do
    {:&, [],
     [
       {:/, [],
        [
          {{:., [], [{:__aliases__, [], module_parts}, fun_name]},
           [no_parens: true], []},
          {:__block__, [], [arity]}
        ]}
     ]}
  end

  defp build_capture(%{type: :local, fun: fun_name, arity: arity}) do
    # Use bare atom for local function name to get correct rendering
    {:&, [],
     [
       {:/, [],
        [
          {fun_name, [], nil},
          {:__block__, [], [arity]}
        ]}
     ]}
  end

  defp create_issue(meta) do
    %Issue{
      rule: :prefer_function_capture,
      message:
        "Single-argument anonymous function delegates to a function call.\n" <>
          "Use function capture syntax instead: &Module.function/1 or &function/1",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
