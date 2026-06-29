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

  # DSL-unsafe in Nx.Defn only: rewrites `fn x -> f(x) end` to `&f/1`. Function
  # captures are restricted inside `defn`/`defnp` bodies, so the rewrite can fail
  # to compile there.
  @impl true
  def unsafe_in_dsl, do: [:nx_defn]
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    captured = captured_fn_positions(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:fn, meta, [{:->, _, [[param], body]}]} = node, issues ->
          with false <- MapSet.member?(captured, position_key(meta)),
               {:ok, _capture_info} <- analyze_fn_body(param, body) do
            {node, [create_issue(meta) | issues]}
          else
            _ -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    captured = captured_fn_positions(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:fn, meta, [{:->, _, [[param], body]}]} = node ->
        with false <- MapSet.member?(captured, position_key(meta)),
             {:ok, capture_info} <- analyze_fn_body(param, body) do
          build_capture(capture_info)
        else
          _ -> node
        end

      node ->
        node
    end)
  end

  # Positions of every `fn` lexically inside a `&` capture. Rewriting such a fn
  # to `&fun/1` would nest it inside the enclosing capture
  # (`&Enum.map(&1, &fun/1)`), which is a compile error ("nested captures are
  # not allowed"). The explicit `fn` was written precisely to avoid that, so we
  # leave it alone. Keyed by `{line, column}`, which is unique per source node.
  defp captured_fn_positions(ast) do
    {_ast, positions} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:&, _, _} = capture, acc ->
          {_c, inner} =
            Macro.prewalk(capture, acc, fn
              {:fn, meta, _} = f, a -> {f, MapSet.put(a, position_key(meta))}
              n, a -> {n, a}
            end)

          {capture, inner}

        node, acc ->
          {node, acc}
      end)

    positions
  end

  defp position_key(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  # Special-form / macro names that are written like a one-argument call but
  # CANNOT be captured: `&var!/1`, `&super/1`, `&unquote/1` are compile errors
  # while `fn x -> var!(x) end` etc. compile and run. They share the regular
  # identifier shape, so the regex below cannot exclude them — list them out.
  @uncapturable_identifiers [:var!, :super, :unquote, :unquote_splicing]

  # Analyze the body of a single-argument fn to see if it's a simple
  # delegation to a function call with the parameter used exactly once.
  #
  # We only admit callees whose name is a plain identifier (`foo`, `foo?`,
  # `foo!`). That is the provably-safe core: `&name/1` reproduces
  # `fn x -> name(x) end` exactly for every regular function AND every
  # capturable macro (verified empirically — remote and local macros both
  # expand inside the capture). The names we must keep out are the
  # special-form *constructors* — `{}` (`:{}`), `<<>>` (`:<<>>`), `%{}`
  # (`:%{}`), `%` (`:%`) — and unary operators, none of which capture; an
  # identifier shape excludes every one of them. The handful of identifier
  # special forms that still slip through are denied by name above.
  defp analyze_fn_body(param, body) do
    param_name = extract_var_name(param)

    case body do
      # Remote function call: Module.function(arg)
      {{:., _, [{:__aliases__, _, module_parts}, fun_name]}, _, args}
      when is_atom(fun_name) and is_list(args) ->
        case args do
          [{var_name, _, nil}] when var_name == param_name ->
            if capturable_name?(fun_name) do
              {:ok, %{type: :remote, module: module_parts, fun: fun_name, arity: 1}}
            else
              :error
            end

          _ ->
            :error
        end

      # Local function call: function(arg)
      {fun_name, _, args} when is_atom(fun_name) and is_list(args) ->
        case args do
          [{var_name, _, nil}] when var_name == param_name ->
            if capturable_name?(fun_name) do
              {:ok, %{type: :local, fun: fun_name, arity: 1}}
            else
              :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  # A plain function identifier: starts with a lowercase letter or underscore,
  # optionally ending in `?`/`!`. Excludes special-form constructors (`:{}`,
  # `:<<>>`, `:%{}`, `:%`), operators (`:+`, `:-`, `:<>`, …) and block forms,
  # then denies the uncapturable identifier special forms by name.
  defp capturable_name?(name)
       when is_atom(name) and name not in @uncapturable_identifiers do
    Regex.match?(~r/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/, Atom.to_string(name))
  end

  defp capturable_name?(_), do: false

  defp extract_var_name({name, _, _}) when is_atom(name), do: name
  defp extract_var_name(_), do: nil

  # Build the AST for the function capture syntax
  defp build_capture(%{type: :remote, module: module_parts, fun: fun_name, arity: arity}) do
    {:&, [],
     [
       {:/, [],
        [
          {{:., [], [{:__aliases__, [], module_parts}, fun_name]}, [no_parens: true], []},
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
