defmodule Credence.Semantic.NoMatchWithMethodStringInPlugRouter do
  @moduledoc """
  Fixes the compile error caused by writing `match "POST", "/path" do` in a
  Plug.Router module.

  LLMs frequently copy Phoenix router syntax into Plug.Router modules, writing
  `match "POST", "/path" do` instead of the correct `post "/path" do`. The
  Plug.Router `match` macro expects a path pattern, not a method string — the
  string gets passed as an AST node to `Plug.Router.__route__/4` which calls
  `Access.get/3` on it, crashing compilation with:

      "no function clause matching in Access.get/3"

  The deterministic fix converts `match "METHOD", "/path" do` to the correct
  method-specific macro (`post`, `get`, `put`, `patch`, `delete`). Methods not
  in the mapping are left as `match`.

  ## Bad

      defmodule ExampleRouterNMWMSIPR do
        use Plug.Router

        match "POST", "/api/webhooks/stripe" do
          send_resp(conn, 200, "ok")
        end
      end

  ## Good

      defmodule ExampleRouterNMWMSIPR do
        use Plug.Router

        post "/api/webhooks/stripe" do
          send_resp(conn, 200, "ok")
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "no function clause matching in Access.get/3"

  @method_mapping %{
    "GET" => :get,
    "POST" => :post,
    "PUT" => :put,
    "PATCH" => :patch,
    "DELETE" => :delete
  }

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc false
  def should_report?(diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, changed} = rewrite(ast, diagnostic)
        changed

      _ ->
        false
    end
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_match_with_method_string_in_plug_router,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} = rewrite(ast, diagnostic)

        if changed, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  defp rewrite(ast, diagnostic) do
    target_line = diagnostic |> Map.get(:position) |> line()

    {new_ast, {changed, _router_stack}} =
      Macro.traverse(
        ast,
        {false, []},
        fn
          {:defmodule, _, [_name, clauses]} = node, {changed, stack} ->
            {node, {changed, [clauses |> module_body() |> uses_plug_router?() | stack]}}

          {:match, meta, [{:__block__, _, [method_str]}, path, do_block]} = node,
          {changed, [true | _] = stack}
          when is_binary(method_str) and is_list(do_block) ->
            method_atom = Map.get(@method_mapping, method_str)

            if method_atom && targeted_line?(target_line, meta[:line]) do
              {{method_atom, meta, [path, do_block]}, {true, stack}}
            else
              {node, {changed, stack}}
            end

          node, acc ->
            {node, acc}
        end,
        fn
          {:defmodule, _, _} = node, {changed, [_current | stack]} ->
            {node, {changed, stack}}

          node, acc ->
            {node, acc}
        end
      )

    {new_ast, changed}
  end

  defp uses_plug_router?({:__block__, _, expressions}),
    do: Enum.any?(expressions, &plug_router_use?/1)

  defp uses_plug_router?(expression), do: plug_router_use?(expression)

  defp module_body(clauses) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  defp plug_router_use?({:use, _, [{:__aliases__, _, [:Plug, :Router]} | _]}), do: true
  defp plug_router_use?(_), do: false

  defp targeted_line?(nil, _node_line), do: false
  defp targeted_line?(line, _node_line) when line <= 0, do: true
  defp targeted_line?(line, line), do: true
  defp targeted_line?(_target_line, _node_line), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line({line, _col}) when is_integer(line), do: line
  defp line(line) when is_integer(line), do: line
  defp line(_), do: nil
end
