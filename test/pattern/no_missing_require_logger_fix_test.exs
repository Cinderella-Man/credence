defmodule Credence.Pattern.NoMissingRequireLoggerFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMissingRequireLogger

  # ═══════════════════════════════════════════════════════════════════
  # Inserts require Logger when missing
  # ═══════════════════════════════════════════════════════════════════

  describe "inserts require Logger" do
    test "function-local require does not satisfy a sibling Logger call" do
      input = """
      defmodule MyAppNMRLSiblingFixScope do
        def first do
          require Logger
          Logger.info("first")
        end

        def second do
          Logger.info("second")
        end
      end
      """

      expected = """
      defmodule MyAppNMRLSiblingFixScope do
        require Logger

        def first do
          require Logger
          Logger.info("first")
        end

        def second do
          Logger.info("second")
        end
      end
      """

      emitted = fix(NoMissingRequireLogger, input)

      confirm_fix(emitted, expected)

      assert Credence.RuleHelpers.compile_and_capture(emitted) ==
               Credence.RuleHelpers.compile_and_capture(expected)
    end

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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), input)
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

      confirm_fix(fix(NoMissingRequireLogger, input), input)
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

      confirm_fix(fix(NoMissingRequireLogger, input), input)
    end

    test "only Logger function calls (no require needed)" do
      input = """
      defmodule MyApp do
        def setup do
          Logger.configure(level: :info)
        end
      end
      """

      confirm_fix(fix(NoMissingRequireLogger, input), input)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
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

      confirm_fix(fix(NoMissingRequireLogger, input), expected)
    end
  end
end
