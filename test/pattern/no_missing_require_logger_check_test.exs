defmodule Credence.Pattern.NoMissingRequireLoggerCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMissingRequireLogger

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — Logger macro used without require
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Logger macro calls without require" do
    test "Logger.info" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.info("starting")
               end
             end
             """)
    end

    test "Logger.debug" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.debug("details")
               end
             end
             """)
    end

    test "Logger.warning" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.warning("watch out")
               end
             end
             """)
    end

    test "Logger.error" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.error("failed")
               end
             end
             """)
    end

    test "Logger.notice" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.notice("fyi")
               end
             end
             """)
    end

    test "Logger.critical" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.critical("bad")
               end
             end
             """)
    end

    test "Logger.alert" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.alert("wake up")
               end
             end
             """)
    end

    test "Logger.emergency" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.emergency("everything is on fire")
               end
             end
             """)
    end

    test "Logger.log/2" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run(level) do
                 Logger.log(level, "message")
               end
             end
             """)
    end

    test "deprecated Logger.warn" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.warn("old style")
               end
             end
             """)
    end

    test "multiple Logger calls, none require" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def start do
                 Logger.info("starting")
               end

               def stop do
                 Logger.debug("stopping")
                 Logger.error("problem")
               end
             end
             """)
    end

    test "Logger in private function" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               defp log_it(msg) do
                 Logger.info(msg)
               end
             end
             """)
    end

    test "Logger inside control flow" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run(x) do
                 if x > 0 do
                   Logger.info("positive")
                 else
                   Logger.warning("non-positive")
                 end
               end
             end
             """)
    end

    test "Logger inside case" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run(result) do
                 case result do
                   {:ok, val} -> Logger.info("got it")
                   {:error, reason} -> Logger.error("failed")
                 end
               end
             end
             """)
    end

    test "Logger with two-argument form (message + metadata)" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.info("msg", request_id: "abc")
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — require / import / use present
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when require Logger is present" do
    test "require Logger at module top" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               require Logger

               def run do
                 Logger.info("starting")
               end
             end
             """)
    end

    test "require Logger after use statement" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               use GenServer
               require Logger

               def run do
                 Logger.info("starting")
               end
             end
             """)
    end

    test "require Logger among other requires" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               require Logger
               require SomeOtherMacro

               def run do
                 Logger.info("starting")
               end
             end
             """)
    end

    test "require Logger co-located with the call inside the same function" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 require Logger
                 Logger.info("starting")
               end
             end
             """)
    end

    test "require Logger in one function does not satisfy a sibling function" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule MyAppNMRLSiblingScope do
               def first do
                 require Logger
                 Logger.info("first")
               end

               def second do
                 Logger.info("second")
               end
             end
             """)
    end
  end

  describe "does not flag when import Logger is present" do
    test "import Logger satisfies require" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               import Logger

               def run do
                 info("starting")
               end
             end
             """)
    end
  end

  describe "does not flag when use Logger is present" do
    test "use Logger satisfies require" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               use Logger

               def run do
                 Logger.info("starting")
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — non-macro Logger functions (no require needed)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag Logger function calls" do
    test "Logger.configure" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               def setup do
                 Logger.configure(level: :info)
               end
             end
             """)
    end

    test "Logger.metadata" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 Logger.metadata(request_id: "abc")
               end
             end
             """)
    end

    test "Logger.level" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 current = Logger.level()
                 IO.inspect(current)
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — no Logger usage at all
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag modules without Logger" do
    test "no Logger calls" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 IO.puts("hello")
               end
             end
             """)
    end

    test "empty module" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
             end
             """)
    end

    test "Logger mentioned only in a string" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyApp do
               def run do
                 IO.puts("Use Logger.info to log")
               end
             end
             """)
    end

    # A Logger call inside a `quote` belongs to the generated code (which carries
    # its own require), not the module defining the macro — so it is not flagged.
    test "Logger macro call inside a quote is not attributed to the defining module" do
      assert clean?(NoMissingRequireLogger, """
             defmodule MyMacros do
               defmacro emit do
                 quote do
                   Logger.info("from generated code")
                 end
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EDGE CASES — multiple modules, nested modules
  # ═══════════════════════════════════════════════════════════════════

  describe "handles multiple modules in one file" do
    test "flags the module that lacks require, not the one that has it" do
      code = """
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

      issues = check(NoMissingRequireLogger, code)
      assert length(issues) == 1
    end
  end

  describe "handles nested modules" do
    # `require Logger` propagates lexically from an enclosing module into nested
    # `defmodule`s (verified: the nested call compiles and runs), so the inner
    # module is satisfied by the outer require and must NOT be flagged.
    test "does not flag an inner module when the outer module has require Logger" do
      assert clean?(NoMissingRequireLogger, """
             defmodule Outer do
               require Logger

               defmodule Inner do
                 def run do
                   Logger.info("from inner")
                 end
               end
             end
             """)
    end

    test "clean when inner module has its own require" do
      assert clean?(NoMissingRequireLogger, """
             defmodule Outer do
               defmodule Inner do
                 require Logger

                 def run do
                   Logger.info("from inner")
                 end
               end
             end
             """)
    end

    # `alias Cluster.Logger` makes `Logger.*` a non-stdlib (function, not macro)
    # call — no `require` needed.
    test "clean when Logger is aliased to a non-stdlib module" do
      assert clean?(NoMissingRequireLogger, """
             defmodule M do
               alias Cluster.Logger

               def run, do: Logger.info("hi")
             end
             """)
    end

    # A custom `use` may inject `require Logger` via its `__using__`.
    test "clean when the module uses a custom (non-stdlib) module" do
      assert clean?(NoMissingRequireLogger, """
             defmodule M do
               use Realtime.Logs

               def run, do: Logger.info("hi")
             end
             """)
    end

    # `require Logger` at file scope (above the defmodule) propagates in.
    test "clean when require Logger is at file scope above the module" do
      assert clean?(NoMissingRequireLogger, """
             require Logger

             defmodule M do
               def run, do: Logger.info("hi")
             end
             """)
    end

    # `use GenServer` (stdlib) does NOT inject require Logger — still flagged.
    test "still flags use GenServer with a Logger call and no require" do
      assert flagged?(NoMissingRequireLogger, """
             defmodule M do
               use GenServer

               def run, do: Logger.info("hi")
             end
             """)
    end

    test "outer uses Logger and has require, inner does not use Logger" do
      assert clean?(NoMissingRequireLogger, """
             defmodule Outer do
               require Logger

               def run do
                 Logger.info("from outer")
               end

               defmodule Inner do
                 def run do
                   :ok
                 end
               end
             end
             """)
    end
  end
end
