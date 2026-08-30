defmodule Credence.Pattern.FixEtsNewStringName do
  @moduledoc """
  Converts a string table name in `:ets.new/2` into the atom it has to be.

  `:ets.new/2` takes an **atom** name. Given a string it raises
  `ArgumentError` — verified by running it, not read off the docs:

      :ets.new("cache", [:set])   # ** (ArgumentError) errors were found at the
                                  #    given arguments
      :ets.new(:erlang.binary_to_atom("cache"), [:set])    # #Reference<...>

  It is a natural mistake in generated code, because almost every other
  "name this thing" API in Elixir takes a string or is happy with either, and
  the failure is at RUNTIME rather than at compile time — the module builds
  clean and dies the first time the table is created.

  ## Equivalence

  The rewrite is a repair rather than a behaviour change, and the distinction is
  the one this project cares about: the "before" raises on **every** input, so
  there is no input on which it returns a value the rewrite could disagree with.
  A rule whose before-code works for somebody is a behaviour change; this one
  works for nobody.

  Only a **literal** string is converted. A variable or an expression is left
  alone — its value is not knowable here, and a name assembled at runtime is
  usually a sign the author wants `:ets.new/2` called with something computed,
  which is a different conversation.

  ## Bad

      defmodule CacheFENSN do
        def start, do: :ets.new("cache", [:set, :named_table])
      end

  ## Good

      defmodule CacheFENSN do
        def start, do: :ets.new(:erlang.binary_to_atom("cache"), [:set, :named_table])
      end
  """
  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case string_name(node) do
          {:ok, name, meta} -> {node, [build_issue(meta, name) | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case fix_patch(node) do
          {:ok, patch} -> {node, [patch | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # `:ets.new("name", opts)` — the erlang module is an atom literal in the AST,
  # not an `__aliases__`, and Sourceror wraps the string in a `:__block__`.
  defp string_name(
         {{:., _, [{:__block__, _, [:ets]}, :new]}, meta, [{:__block__, _, [name]}, _opts]}
       )
       when is_binary(name) do
    # Only report what the fix will actually repair. A name that cannot be
    # written as a bare atom (`"my table"`, `""`) is declined by `fix_node/1`,
    # and reporting it anyway produced a `:no_op` — a finding raised and left
    # unfixed, which is the one shape this project's "fix or drop it" policy
    # exists to prevent. The check and the fix share `valid_atom_name?/1` so
    # they cannot disagree.
    if valid_atom_name?(name), do: {:ok, name, meta}, else: :error
  end

  defp string_name(_node), do: :error

  defp fix_patch(
         {{:., _, [{:__block__, _, [:ets]}, :new]}, _,
          [{:__block__, _, [name]} = name_node, _opts]}
       )
       when is_binary(name) do
    # Declining a name that cannot be written as a bare atom (`"my table"`,
    # `""`) is deliberate. `:"my table"` would compile, but quoting is a
    # decision about how the table should be named, and this rule's whole
    # warrant is that the atom form is what the author obviously meant.
    # `check/2` declines the same names, so nothing is reported here unfixed.
    if valid_atom_name?(name) do
      replacement = ":erlang.binary_to_atom(" <> inspect(name) <> ")"
      {:ok, %{range: Sourceror.get_range(name_node), change: replacement}}
    else
      :error
    end
  end

  defp fix_patch(_node), do: :error

  # A name that renders as a bare atom: `:cache`, `:my_cache`, `:cache?`.
  @bare_atom ~r/^[a-z_][A-Za-z0-9_]*[?!]?$/

  defp valid_atom_name?(name), do: Regex.match?(@bare_atom, name)

  defp build_issue(meta, name) do
    %Issue{
      rule: :fix_ets_new_string_name,
      message:
        "`:ets.new/2` requires an atom table name and raises ArgumentError on a " <>
          "string. Convert `\"#{name}\"` to `:#{name}` at runtime.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # Nothing here touches a construct any macro DSL reinterprets: the rewrite
  # replaces a string literal argument to a specific erlang call with an atom.
  # `Ash.Expr`, `Ecto.Query` and `Nx.defn` all leave `:ets.new/2` alone.
  @impl true
  def unsafe_in_dsl, do: []
end
