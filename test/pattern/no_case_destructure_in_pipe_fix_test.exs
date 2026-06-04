defmodule Credence.Pattern.NoCaseDestructureInPipeFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseDestructureInPipe

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoCaseDestructureInPipe.fix_patches(ast, source: code)

    case patches do
      [] -> code
      _ -> Sourceror.patch_string(code, patches)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — irrefutable variable patterns rewrite to then/1.
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites irrefutable single-clause case to then/1" do
    test "bare variable pattern" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> case do
            value -> value + 1
          end
        end
      end
      """

      expected = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> then(fn value -> value + 1 end)
        end
      end
      """

      assert fix(code) == expected
    end

    test "underscore wildcard pattern" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> case do
            _ -> 42
          end
        end
      end
      """

      expected = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> then(fn _ -> 42 end)
        end
      end
      """

      assert fix(code) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OP — refutable / out-of-scope shapes are left untouched.
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves unsafe and out-of-scope shapes untouched" do
    test "tuple destructure pattern (refutable)" do
      code = """
      defmodule X do
        def process(list) do
          list
          |> reduce()
          |> case do
            {sum, count} -> sum / count
          end
        end
      end
      """

      assert fix(code) == code
    end

    test "tagged-tuple pattern (refutable)" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> fetch()
          |> case do
            {:ok, result} -> result
          end
        end
      end
      """

      assert fix(code) == code
    end

    test "guarded variable pattern (refutable)" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> compute()
          |> case do
            v when v > 0 -> v
          end
        end
      end
      """

      assert fix(code) == code
    end

    test "multi-clause case in pipe" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> compute()
          |> case do
            value -> value + 1
            other -> other
          end
        end
      end
      """

      assert fix(code) == code
    end
  end
end
