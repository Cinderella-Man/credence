defmodule Credence.DslGuardTest do
  @moduledoc """
  Detection unit tests for `Credence.DslGuard`.

  The guard's job is to range macro blocks that reinterpret plain Elixir AST.
  Detection is by call *shape*, not by import, so it must survive `use` wrappers,
  scoped imports and aliases (under-detection ships a wrong fix), while never
  mistaking an ordinary function named `select`/`from`/`dynamic` for a query
  (over-detection forgoes a safe fix).
  """
  use ExUnit.Case, async: true

  alias Credence.DslGuard

  defp ranges(src), do: src |> Sourceror.parse_string!() |> DslGuard.block_ranges()
  defp inside?(src, line), do: DslGuard.inside_block?(line, ranges(src))

  describe "Ash expr — robust to use-wrappers and aliases" do
    test "ranges expr/1 even with no import (use MyAppWeb wrapper hides it)" do
      src = """
      defmodule M do
        use MyAppWeb, :resource

        def calc, do: expr(
          if route.status in [:a, :b] do
            false
          else
            exists(orders, status == :pending)
          end
        )
      end
      """

      # the rewritten `if` (line 5) sits inside the expr block
      assert inside?(src, 5)
    end

    test "ranges an aliased Ash.Expr call" do
      src = """
      defmodule M do
        alias Ash.Expr
        def f(r), do: Expr.expr(not r.active)
      end
      """

      assert inside?(src, 3)
    end
  end

  describe "Ash bare macros (filter/calculate/aggregate) — via import/use signal" do
    test "ranges a bare imported filter/2 body (import Ash.Query present)" do
      src = """
      defmodule M do
        import Ash.Query
        def q(query), do: filter(query,
          if is_nil(x) do false else visible end)
      end
      """

      # the reinterpreted `if` (line 4) sits inside the bare `filter` expression
      assert inside?(src, 4)
    end

    test "ranges a piped filter body when the module uses an Ash.* module" do
      src = """
      defmodule M do
        use Ash.Resource
        def q(query), do: query |> filter(
          if is_nil(x) do false else visible end)
      end
      """

      assert inside?(src, 4)
    end

    test "does NOT range a bare filter when no Ash import/use is present" do
      # A plain `filter/2` helper in an ordinary module must stay fixable.
      src = """
      defmodule M do
        def filter(query, cond), do: apply_filter(query, cond)
        def run(q), do: filter(q, x == 1)
      end
      """

      assert ranges(src) == []
      refute inside?(src, 3)
    end
  end

  describe "Ecto query — shape-based, import-independent" do
    test "ranges pipe-form where/2 by its binding list, with no import" do
      src = """
      defmodule M do
        use MyAppWeb, :schema
        def q(query, h), do:
          where(query, [transaction], transaction.block_hash == ^h)
      end
      """

      assert inside?(src, 4)
    end

    test "ranges from(x in Y, ...) keyword query (covers its where:/select:)" do
      src = """
      defmodule M do
        def q, do: from(p in Post,
          where: p.x == ^1,
          select: p.y)
      end
      """

      assert inside?(src, 3)
    end

    test "ranges an aliased Ecto.Query call" do
      src = """
      defmodule M do
        alias Ecto.Query, as: Q
        def q(c), do: Q.from(p in c, where: p.x == ^1)
      end
      """

      assert inside?(src, 3)
    end
  end

  describe "Nx defn — body is reinterpreted" do
    test "ranges a defn body" do
      src = """
      defmodule M do
        import Nx.Defn
        defn f(a, b) do
          a + b
        end
      end
      """

      assert inside?(src, 4)
    end
  end

  describe "no over-detection on plain code (collisions)" do
    test "an ordinary function named select/1 is not DSL" do
      src = """
      defmodule M do
        def select(opts), do: Keyword.get(opts, :x)
        def run(o), do: select(o)
      end
      """

      refute inside?(src, 3)
      assert ranges(src) == []
    end

    test "a def head named dynamic is not ranged" do
      src = """
      defmodule M do
        def dynamic(descr) do
          descr + 1
        end
      end
      """

      refute inside?(src, 2)
    end

    test "a pipe-form name with no binding list is not a query" do
      # `update(state, fun)` without a `[binding]` arg is just a function call.
      src = """
      defmodule M do
        def step(state), do: update(state, fn s -> s + 1 end)
      end
      """

      refute inside?(src, 2)
    end

    test "a namesake call whose list variable is never referenced is not a query" do
      # Real libraries define their own select/group_by/join; the list is DATA, not
      # a query binding, so its variable is never referenced elsewhere in the call.
      # Flagging these would drop a safe fix (not compile-gate-backstopped).
      for src <- [
            # Explorer (DataFrames): select(df, [column]) / group_by(df, [group], opts)
            "defmodule M do\n  def sel(df, column), do: select(df, [column])\nend\n",
            "defmodule M do\n  def grp(df, group, opts), do: group_by(df, [group], opts)\nend\n",
            # a string/path join helper:
            "defmodule M do\n  def j(joiner, a, b), do: join(joiner, [a, b])\nend\n",
            # a callback binder — [x, y] aren't referenced in the handler:
            "defmodule M do\n  def bind(x, y, c), do: on([x, y], if(c, do: 1, else: 2))\nend\n"
          ] do
        assert ranges(src) == [], "expected no DSL block for: #{src}"
      end
    end
  end

  describe "Ecto query — recognised by the binding being referenced, or `in`" do
    test "a binding used via `in` (join) is a query" do
      src = """
      defmodule M do
        def q(query), do:
          join(query, :inner, [p], c in assoc(p, :comments))
      end
      """

      assert inside?(src, 3)
    end

    test "selecting whole rows (`[p], p`) IS a query — the binding is referenced" do
      src = "defmodule M do\n  def q(query), do: select(query, [p], p)\nend\n"
      assert inside?(src, 2)
    end

    test "an explicit empty binding with a pin is a query (`where(q, [], ^cond)`)" do
      src = "defmodule M do\n  def q(query, cond), do: where(query, [], ^cond)\nend\n"
      assert inside?(src, 2)
    end

    test "a declared-but-unused binding with a pin is a query (`where(q, [p], ^dyn)`)" do
      src = "defmodule M do\n  def q(query, dyn), do: where(query, [p], ^dyn)\nend\n"
      assert inside?(src, 2)
    end

    test "an empty list with no query signal is not a query (`where(state, [])`)" do
      # `[]` on its own is too common a value to treat as a binding.
      for src <- [
            "defmodule M do\n  def w(state), do: where(state, [])\nend\n",
            "defmodule M do\n  def s(data, opts), do: select(data, [], opts)\nend\n"
          ] do
        assert ranges(src) == [], "expected no DSL block for: #{src}"
      end
    end
  end

  describe "Ecto bindingless forms — recognised by a pin (`^`)" do
    test "the bare keyword-shorthand `where(q, id: ^id)` is a query" do
      # Ecto reads a 2-arg `where(q, expr)` as an empty binding; the pin is the
      # only reliable, collision-free signal (it can't occur in compiling plain code).
      for src <- [
            "defmodule M do\n  def q(query, id), do: where(query, id: ^id)\nend\n",
            "defmodule M do\n  def q(query, dyn), do: where(query, ^dyn)\nend\n",
            "defmodule M do\n  def q(query, ord), do: order_by(query, ^ord)\nend\n"
          ] do
        assert inside?(src, 2), "expected a DSL block for: #{src}"
      end
    end

    test "a plain 2-arg call with a bare `in` (no marker, no pin) is not a query" do
      # `x in allowed` is ordinary membership — `in` is trusted only with a binding
      # marker, so a bindingless `where(items, x in allowed)` stays plain.
      for src <- [
            "defmodule M do\n  def w(items, allowed), do: where(items, x in allowed)\nend\n",
            "defmodule M do\n  def w(state, c), do: where(state, c)\nend\n",
            "defmodule M do\n  def s(data, opts), do: select(data, opts)\nend\n"
          ] do
        assert ranges(src) == [], "expected no DSL block for: #{src}"
      end
    end
  end

  describe "patch_blocked?/2 — intersection, not just containment" do
    setup do
      rs = ranges("defmodule M do\n  def c, do: expr(\n    if x do false else y end)\nend\n")
      {:ok, ranges: rs}
    end

    test "a patch inside the expr block is blocked", %{ranges: rs} do
      assert DslGuard.patch_blocked?(%{start: [line: 3, column: 5], end: [line: 3, column: 25]}, rs)
    end

    test "a patch entirely outside is allowed", %{ranges: rs} do
      refute DslGuard.patch_blocked?(%{start: [line: 1, column: 1], end: [line: 1, column: 5]}, rs)
    end

    test "a patch with no range is allowed", %{ranges: rs} do
      refute DslGuard.patch_blocked?(%{change: "x"}, rs)
    end
  end

  describe "patch_blocked?/3 — an enclosing patch is allowed only if the block survives verbatim (#5b)" do
    @enclose_range %{start: [line: 1, column: 1], end: [line: 4, column: 4]}

    test "an enclosing patch that carries the blocks through verbatim is NOT blocked" do
      blocks = ranges("def f do\n  a = expr(x == ^y)\n  b = expr(x == ^z)\nend\n")
      patch = %{range: @enclose_range, change: "def f do\n  b = expr(x == ^z)\n  a = expr(x == ^y)\nend"}
      refute DslGuard.patch_blocked?(patch, blocks, [:ash_expr])
    end

    test "an enclosing patch that reshapes a block IS blocked" do
      blocks = ranges("def f do\n  a = expr(x == ^y)\n  b = expr(x == ^z)\nend\n")
      patch = %{range: @enclose_range, change: "def f do\n  b = expr(x == ^z)\n  a = expr(x != ^y)\nend"}
      assert DslGuard.patch_blocked?(patch, blocks, [:ash_expr])
    end

    test "aliasing: two identical blocks, one reshaped, is blocked (not masked by its twin)" do
      blocks = ranges("def f do\n  a = expr(x == ^y)\n  b = expr(x == ^y)\nend\n")
      patch = %{range: @enclose_range, change: "def f do\n  b = expr(x == ^y)\n  a = expr(x != ^y)\nend"}
      assert DslGuard.patch_blocked?(patch, blocks, [:ash_expr])
    end
  end

  describe "configuration" do
    test "config-listed names are treated as always-DSL" do
      src = "defmodule M do\n  def f, do: my_query(a > 1)\nend\n"
      ast = Sourceror.parse_string!(src)

      refute DslGuard.inside_block?(2, DslGuard.block_ranges(ast))
      assert DslGuard.inside_block?(2, DslGuard.block_ranges(ast, dsl_macros: [:my_query]))
    end
  end
end
