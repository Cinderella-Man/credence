defmodule Credence.Pattern.NoDestructureReconstructFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDestructureReconstruct

  describe "fix/2 — case branches" do
    test "replaces reconstructed list with binding variable" do
      input = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      expected = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [_, _, _, _] = items ->
              Enum.all?(items, &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end

    test "fixes two-variable case" do
      input = """
      defmodule Bad do
        def swap(input) do
          case String.split(input, ":") do
            [a, b] -> Enum.join([a, b], "-")
            _ -> input
          end
        end
      end
      """

      expected = """
      defmodule Bad do
        def swap(input) do
          case String.split(input, ":") do
            [_, _] = items -> Enum.join(items, "-")
            _ -> input
          end
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end
  end

  describe "fix/2 — function heads" do
    test "fixes def function head" do
      input = """
      defmodule Bad do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end
      """

      expected = """
      defmodule Bad do
        def process([_, _, _] = items) do
          Enum.map(items, &(&1 * 2))
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end

    test "fixes defp function head" do
      input = """
      defmodule Bad do
        defp transform([first, second]) do
          Enum.join([first, second], ",")
        end
      end
      """

      expected = """
      defmodule Bad do
        defp transform([_, _] = items) do
          Enum.join(items, ",")
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end

    test "fixes guarded function head" do
      input = """
      defmodule Bad do
        def validate([a, b, c, d]) when is_binary(a) do
          Enum.all?([a, b, c, d], &is_binary/1)
        end
      end
      """

      expected = """
      defmodule Bad do
        def validate([a, _, _, _] = items) when is_binary(a) do
          Enum.all?(items, &is_binary/1)
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end
  end

  describe "fix/2 — partial variable usage" do
    test "keeps individually-used variables, underscores the rest" do
      input = """
      defmodule Bad do
        def check(input) do
          case String.split(input, ",") do
            [a, b, c] ->
              Logger.info(a)
              Enum.max([a, b, c])
            _ ->
              :error
          end
        end
      end
      """

      expected = """
      defmodule Bad do
        def check(input) do
          case String.split(input, ",") do
            [a, _, _] = items ->
              Logger.info(a)
              Enum.max(items)
            _ ->
              :error
          end
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end

    test "keeps multiple individually-used variables" do
      input = """
      defmodule Bad do
        def run(data) do
          case data do
            [x, y, z] ->
              IO.puts(x)
              IO.puts(z)
              Enum.sum([x, y, z])
          end
        end
      end
      """

      expected = """
      defmodule Bad do
        def run(data) do
          case data do
            [x, _, z] = items ->
              IO.puts(x)
              IO.puts(z)
              Enum.sum(items)
          end
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, input), expected)
    end
  end

  describe "fix/2 — edge cases" do
    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Good do
        def process(list) do
          Enum.map(list, &to_string/1)
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, code), code)
    end

    test "does not touch already-idiomatic code" do
      code = """
      defmodule Good do
        def check(ip) do
          case String.split(ip, ".") do
            [_, _, _, _] = parts ->
              Enum.all?(parts, &valid_octet?/1)

            _ ->
              false
          end
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, code), code)
    end

    # Reassigning a destructured variable before reconstruction would make the
    # `= items` collapse return stale input — the fix must leave it untouched.
    test "does not rewrite when a destructured variable is reassigned" do
      code = """
      defmodule Good do
        defp normalize([language, script, territory]) do
          script = maybe_nil_script(script, territory)
          [language, script, territory]
        end
      end
      """

      confirm_fix(fix(NoDestructureReconstruct, code), code)
    end

    test "round-trip: case branch fix produces zero issues" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      assert check(NoDestructureReconstruct, fix(NoDestructureReconstruct, code)) == []
    end

    test "round-trip: function head fix produces zero issues" do
      code = """
      defmodule Bad do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end
      """

      assert check(NoDestructureReconstruct, fix(NoDestructureReconstruct, code)) == []
    end
  end
end
