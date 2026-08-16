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

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_match_with_method_string_in_plug_router,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            # match "METHOD", "/path" do ... end -> method "/path" do ... end
            {:match, meta, [{:__block__, _, [method_str]}, path, do_block]}, acc
            when is_binary(method_str) and is_list(do_block) ->
              case Map.get(@method_mapping, method_str) do
                nil ->
                  # Unknown method, leave as match
                  {{:match, meta, [{:__block__, [], [method_str]}, path, do_block]}, acc}

                method_atom ->
                  {{method_atom, meta, [path, do_block]}, true}
              end

            node, acc ->
              {node, acc}
          end)

        if changed, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
