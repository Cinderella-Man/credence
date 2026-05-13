defmodule Credence.Pattern.NoMissingRequireLoggerFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NoMissingRequireLogger.fix(code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # Inserts require Logger when missing
  # ═══════════════════════════════════════════════════════════════════

  describe "inserts require Logger" do
    test "basic module with Logger.info" do
      input = """
      defmodule MyApp do
        def run do
          Logger.info("starting")
        end
      end
      """

      expected = """
      defmodule MyApp do
        require Logger

        def run do
          Logger.info("starting")
        end
      end
      """

      assert fix(input) == expected
    end

    test "places require after existing use statement" do
      input = """
      defmodule MyApp do
        use GenServer

        def run do
          Logger.info("starting")
        end
      end
      """

      expected = """
      defmodule MyApp do
        use GenServer

        require Logger

        def run do
          Logger.info("starting")
        end
      end
      """

      assert fix(input) == expected
    end

    test "places require after existing alias block" do
      input = """
      defmodule MyApp do
        alias MyApp.Repo
        alias MyApp.Schema

        def run do
          Logger.info("starting")
        end
      end
      """

      expected = """
      defmodule MyApp do
        alias MyApp.Repo
        alias MyApp.Schema

        require Logger

        def run do
          Logger.info("starting")
        end
      end
      """

      assert fix(input) == expected
    end

    test "places require after mixed directives" do
      input = """
      defmodule MyApp do
        use GenServer
        alias MyApp.Repo
        import Ecto.Query

        def run do
          Logger.warning("hmm")
        end
      end
      """

      expected = """
      defmodule MyApp do
        use GenServer
        alias MyApp.Repo
        import Ecto.Query

        require Logger

        def run do
          Logger.warning("hmm")
        end
      end
      """

      assert fix(input) == expected
    end

    test "places require after existing require" do
      input = """
      defmodule MyApp do
        require SomeMacro

        def run do
          Logger.error("oh no")
        end
      end
      """

      expected = """
      defmodule MyApp do
        require SomeMacro

        require Logger

        def run do
          Logger.error("oh no")
        end
      end
      """

      assert fix(input) == expected
    end

    test "handles module with only Logger calls, no directives" do
      input = """
      defmodule MyApp do
        def run do
          Logger.debug("running")
        end
      end
      """

      expected = """
      defmodule MyApp do
        require Logger

        def run do
          Logger.debug("running")
        end
      end
      """

      assert fix(input) == expected
    end

    test "handles multiple Logger calls — inserts only one require" do
      input = """
      defmodule MyApp do
        def start do
          Logger.info("starting")
        end

        def stop do
          Logger.info("stopping")
          Logger.error("problem")
        end
      end
      """

      expected = """
      defmodule MyApp do
        require Logger

        def start do
          Logger.info("starting")
        end

        def stop do
          Logger.info("stopping")
          Logger.error("problem")
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Does not modify clean code
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify when require already present" do
    test "require Logger exists" do
      input = """
      defmodule MyApp do
        require Logger

        def run do
          Logger.info("starting")
        end
      end
      """

      assert fix(input) == input
    end

    test "import Logger exists" do
      input = """
      defmodule MyApp do
        import Logger

        def run do
          info("starting")
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify modules without Logger macros" do
    test "no Logger usage" do
      input = """
      defmodule MyApp do
        def run do
          IO.puts("hello")
        end
      end
      """

      assert fix(input) == input
    end

    test "only Logger function calls (no require needed)" do
      input = """
      defmodule MyApp do
        def setup do
          Logger.configure(level: :info)
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
    test "fixes only the module missing require" do
      input = """
      defmodule Clean do
        require Logger

        def run do
          Logger.info("ok")
        end
      end

      defmodule Dirty do
        def run do
          Logger.info("missing require")
        end
      end
      """

      expected = """
      defmodule Clean do
        require Logger

        def run do
          Logger.info("ok")
        end
      end

      defmodule Dirty do
        require Logger

        def run do
          Logger.info("missing require")
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "handles moduledoc and doc attributes" do
    test "places require after moduledoc but before functions" do
      input = """
      defmodule MyApp do
        @moduledoc "My application"

        def run do
          Logger.info("starting")
        end
      end
      """

      expected = """
      defmodule MyApp do
        @moduledoc "My application"

        require Logger

        def run do
          Logger.info("starting")
        end
      end
      """

      assert fix(input) == expected
    end

    test "places require after moduledoc and use" do
      input = """
      defmodule MyApp do
        @moduledoc "My application"
        use GenServer

        def run do
          Logger.info("starting")
        end
      end
      """

      expected = """
      defmodule MyApp do
        @moduledoc "My application"
        use GenServer

        require Logger

        def run do
          Logger.info("starting")
        end
      end
      """

      assert fix(input) == expected
    end
  end
end
