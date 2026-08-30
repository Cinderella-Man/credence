defmodule Credence.Semantic.FixPlugDependencyModuleOrder do
  @moduledoc """
  Fixes compiler errors when a `plug SomeModule` call appears in a `Plug.Router`
  module defined before the dependency module in the same file.

  `Plug.Builder` calls `init/1` at compile time, so the plugged module must be
  compiled first. When the dependency module is defined after the router, the
  compiler emits:

      function SomeModule.init/1 is undefined (module SomeModule is not available)

  The fix reorders module definitions so the dependency module comes first.

  Only top-level (column-0) module definitions are reordered, and only when the
  dependency module starts strictly after the plug-calling module ends — nested
  or overlapping definitions are left untouched.

  ## Bad

      defmodule MediaVersionApi.Router do
        use Plug.Router
        import Plug.Conn

        plug(MediaVersionApi.Plugs.AcceptVersion)
        plug(:match)
        plug(:dispatch)

        get "/hello" do
          send_resp(conn, 200, "world")
        end
      end

      defmodule MediaVersionApi.Plugs.AcceptVersion do
        @behaviour Plug

        @impl true
        def init(opts), do: opts

        @impl true
        def call(conn, _opts), do: conn
      end

  ## Good

      defmodule MediaVersionApi.Plugs.AcceptVersion do
        @behaviour Plug

        @impl true
        def init(opts), do: opts

        @impl true
        def call(conn, _opts), do: conn
      end

      defmodule MediaVersionApi.Router do
        use Plug.Router
        import Plug.Conn

        plug(MediaVersionApi.Plugs.AcceptVersion)
        plug(:match)
        plug(:dispatch)

        get "/hello" do
          send_resp(conn, 200, "world")
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # The module in `(module ... is not available)` must be the same module the
  # `init/1` call was made on — the backreference pins that.
  @diag_re ~r/function\s+([\w.]+)\.init\/1\s+is\s+undefined\s+\(module\s+\1\s+is\s+not\s+available\)/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(@diag_re, msg)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually reorder the source, so files where the dependency
  module is missing, nested, or already defined first are not attributed to
  this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_plug_dependency_module_order,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    case extract_module_name(msg) do
      {:ok, module_name} -> reorder_modules(source, module_name)
      :error -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Extract the module name from "function Module.init/1 is undefined (module Module is not available)"
  defp extract_module_name(msg) do
    case Regex.run(@diag_re, msg) do
      [_, mod_str] -> {:ok, mod_str}
      _ -> :error
    end
  end

  # Reorder module definitions so the dependency module comes first.
  defp reorder_modules(source, module_name) do
    lines = String.split(source, "\n")
    shadow_lines = source |> SourceMask.mask() |> String.split("\n")

    with {:ok, dep_start, dep_end} <- find_module_range(shadow_lines, module_name),
         {:ok, user_start, user_end} <- find_using_module_range(shadow_lines, module_name),
         true <- dep_start > user_end do
      do_reorder(lines, dep_start, dep_end, user_start, user_end)
    else
      _ -> source
    end
  end

  # Find the line range (1-indexed) of a top-level defmodule block by its
  # module name. Column-0 only: an indented (nested) definition cannot be
  # safely moved to the top level.
  defp find_module_range(lines, module_name) do
    alias_pattern = Regex.escape(module_name)

    Enum.find_value(Enum.with_index(lines, 1), :error, fn {line, idx} ->
      if Regex.match?(~r/^defmodule\s+#{alias_pattern}\s+do\s*$/, line) do
        case find_matching_end(lines, idx) do
          {:ok, end_idx} -> {:ok, idx, end_idx}
          :error -> nil
        end
      end
    end)
  end

  # Find the top-level defmodule whose body contains a `plug DependencyModule`
  # call.
  defp find_using_module_range(lines, module_name) do
    # Try full module name first, then short alias (last segment).
    # After `alias Foo.Bar.Baz`, a `plug Baz` call resolves to `Foo.Bar.Baz`.
    short_name = module_name |> String.split(".") |> List.last()

    patterns =
      if short_name == module_name do
        [plug_pattern(module_name)]
      else
        [plug_pattern(module_name), plug_pattern(short_name)]
      end

    Enum.find_value(patterns, :error, fn plug_pattern ->
      case find_plug_caller(lines, plug_pattern) do
        {:ok, _, _} = result -> result
        :error -> nil
      end
    end)
  end

  defp plug_pattern(name), do: ~r/^\s*plug[\s(]+#{Regex.escape(name)}\b/

  defp find_plug_caller(lines, plug_pattern) do
    module_ranges = top_level_module_ranges(lines)

    Enum.find_value(Enum.with_index(lines, 1), :error, fn {line, idx} ->
      if Regex.match?(plug_pattern, line) do
        case enclosing_range(module_ranges, idx) do
          {:ok, _, _} = result -> result
          :error -> nil
        end
      end
    end)
  end

  # All column-0 `defmodule ... do` blocks with a resolvable matching `end`.
  defp top_level_module_ranges(lines) do
    Enum.flat_map(Enum.with_index(lines, 1), fn {line, idx} ->
      if Regex.match?(~r/^defmodule\s+[\w.]+\s+do\s*$/, line) do
        case find_matching_end(lines, idx) do
          {:ok, end_idx} -> [{idx, end_idx}]
          :error -> []
        end
      else
        []
      end
    end)
  end

  # The innermost range strictly containing `line_no`. Walking backwards to
  # the nearest `defmodule` line is not enough — that would pick an already
  # closed sibling (e.g. a nested helper module defined before the plug call).
  defp enclosing_range(ranges, line_no) do
    ranges
    |> Enum.filter(fn {s, e} -> s < line_no and line_no < e end)
    |> case do
      [] ->
        :error

      containing ->
        {s, e} = Enum.max_by(containing, fn {s, _e} -> s end)
        {:ok, s, e}
    end
  end

  # Find the matching `end` for a `defmodule ... do` starting at start_line.
  defp find_matching_end(lines, start_line) do
    start_indent = get_indent(Enum.at(lines, start_line - 1, ""))
    do_find_end(lines, start_line + 1, start_indent, 0)
  end

  defp do_find_end(lines, idx, _start_indent, _depth) when idx > length(lines), do: :error

  defp do_find_end(lines, idx, start_indent, depth) do
    line = Enum.at(lines, idx - 1, "")
    trimmed = String.trim(line)

    cond do
      Regex.match?(~r/\bdo\s*$/, trimmed) ->
        do_find_end(lines, idx + 1, start_indent, depth + 1)

      trimmed == "end" and get_indent(line) == start_indent and depth == 0 ->
        {:ok, idx}

      trimmed == "end" ->
        do_find_end(lines, idx + 1, start_indent, depth - 1)

      true ->
        do_find_end(lines, idx + 1, start_indent, depth)
    end
  end

  # Reorder: move the dependency module before the user module.
  defp do_reorder(lines, dep_start, dep_end, user_start, user_end) do
    total = length(lines)

    before = if user_start > 1, do: Enum.slice(lines, 0..(user_start - 2)), else: []
    user_mod = Enum.slice(lines, (user_start - 1)..(user_end - 1))
    gap = if user_end < dep_start - 1, do: Enum.slice(lines, user_end..(dep_start - 2)), else: []
    dep_mod = Enum.slice(lines, (dep_start - 1)..(dep_end - 1))
    after_dep = if dep_end < total, do: Enum.slice(lines, dep_end..(total - 1)), else: []

    new_lines =
      if Enum.all?(gap, &(String.trim(&1) == "")) do
        before ++ dep_mod ++ gap ++ user_mod ++ after_dep
      else
        {leading_space, gap_code} = Enum.split_while(gap, &(String.trim(&1) == ""))
        before ++ gap_code ++ dep_mod ++ leading_space ++ user_mod ++ after_dep
      end

    Enum.join(new_lines, "\n")
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
