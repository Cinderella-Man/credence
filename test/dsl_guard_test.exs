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

  describe "configuration" do
    test "config-listed names are treated as always-DSL" do
      src = "defmodule M do\n  def f, do: my_query(a > 1)\nend\n"
      ast = Sourceror.parse_string!(src)

      refute DslGuard.inside_block?(2, DslGuard.block_ranges(ast))
      assert DslGuard.inside_block?(2, DslGuard.block_ranges(ast, dsl_macros: [:my_query]))
    end
  end
end
