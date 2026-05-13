defmodule Credence.Semantic.MissingUseExUnitCaseFixTest do
  use ExUnit.Case

  alias Credence.Semantic.MissingUseExUnitCase

  # The diagnostic is passed to fix/2 but the rule doesn't use it
  # for positioning — it finds missing `use` via AST analysis.
  @diagnostic %{
    severity: :error,
    message: "undefined function describe/2 (there is no such import)",
    position: 2
  }

  defp fix(code) do
    result = MissingUseExUnitCase.fix(code, @diagnostic)
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # Inserts use ExUnit.Case when missing
  # ═══════════════════════════════════════════════════════════════════

  describe "inserts use ExUnit.Case" do
    test "module with describe and test blocks" do
      input = """
      defmodule MyAppTest do
        describe "feature" do
          test "works" do
            assert true
          end
        end
      end
      """

      expected = """
      defmodule MyAppTest do
        use ExUnit.Case

        describe "feature" do
          test "works" do
            assert true
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "module with only test blocks (no describe)" do
      input = """
      defmodule MyAppTest do
        test "works" do
          assert true
        end

        test "also works" do
          assert 1 + 1 == 2
        end
      end
      """

      expected = """
      defmodule MyAppTest do
        use ExUnit.Case

        test "works" do
          assert true
        end

        test "also works" do
          assert 1 + 1 == 2
        end
      end
      """

      assert fix(input) == expected
    end

    test "module with setup block" do
      input = """
      defmodule MyAppTest do
        setup do
          {:ok, value: 42}
        end

        test "uses setup", %{value: value} do
          assert value == 42
        end
      end
      """

      expected = """
      defmodule MyAppTest do
        use ExUnit.Case

        setup do
          {:ok, value: 42}
        end

        test "uses setup", %{value: value} do
          assert value == 42
        end
      end
      """

      assert fix(input) == expected
    end

    test "places use after existing @moduledoc" do
      input = """
      defmodule MyAppTest do
        @moduledoc false

        test "works" do
          assert true
        end
      end
      """

      expected = """
      defmodule MyAppTest do
        @moduledoc false

        use ExUnit.Case

        test "works" do
          assert true
        end
      end
      """

      assert fix(input) == expected
    end

    test "places use after existing directives" do
      input = """
      defmodule MyAppTest do
        alias MyApp.Repo
        import MyApp.Helpers

        describe "feature" do
          test "works" do
            assert true
          end
        end
      end
      """

      expected = """
      defmodule MyAppTest do
        alias MyApp.Repo
        import MyApp.Helpers

        use ExUnit.Case

        describe "feature" do
          test "works" do
            assert true
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "places use after existing require" do
      input = """
      defmodule MyAppTest do
        require Logger

        test "logs" do
          Logger.info("test")
          assert true
        end
      end
      """

      expected = """
      defmodule MyAppTest do
        require Logger

        use ExUnit.Case

        test "logs" do
          Logger.info("test")
          assert true
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Does not modify clean code
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify when use ExUnit.Case is present" do
    test "already has use ExUnit.Case" do
      input = """
      defmodule MyAppTest do
        use ExUnit.Case

        test "works" do
          assert true
        end
      end
      """

      assert fix(input) == input
    end

    test "has use ExUnit.Case with async option" do
      input = """
      defmodule MyAppTest do
        use ExUnit.Case, async: true

        test "works" do
          assert true
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify modules without ExUnit calls" do
    test "regular module" do
      input = """
      defmodule MyApp do
        def run do
          IO.puts("hello")
        end
      end
      """

      assert fix(input) == input
    end

    test "module with a function named test (not ExUnit macro)" do
      input = """
      defmodule MyApp do
        def test(value) do
          value > 0
        end
      end
      """

      assert fix(input) == input
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "handles multiple modules in one file" do
    test "fixes only the module missing use ExUnit.Case" do
      input = """
      defmodule CleanTest do
        use ExUnit.Case

        test "ok" do
          assert true
        end
      end

      defmodule DirtyTest do
        test "missing use" do
          assert true
        end
      end
      """

      expected = """
      defmodule CleanTest do
        use ExUnit.Case

        test "ok" do
          assert true
        end
      end

      defmodule DirtyTest do
        use ExUnit.Case

        test "missing use" do
          assert true
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "does not confuse regular functions with ExUnit macros" do
    test "def test(...) is not ExUnit's test macro" do
      input = """
      defmodule Helpers do
        def test(conn, path) do
          get(conn, path)
        end
      end
      """

      assert fix(input) == input
    end
  end
end
