defmodule Credence.CompileBoundsTest do
  # `async: false`: the bounds live in application env so they can be perturbed,
  # and a parallel test compiling under someone else's ceiling would be flaky.
  use ExUnit.Case, async: false

  alias Credence.RuleHelpers

  @moduledoc """
  `compile_and_capture/1` executes the source it is handed, so it must survive
  source that does not intend to finish.

  The defect these pin: `Enum.flat_map(1..10, &Stream.cycle([&1]))` — the
  *expected output* of one of `UndefinedFunction`'s own fix tests — materialises
  an infinite stream. Harvested as a pipeline-witness candidate and compiled, it
  took the VM from 200 MB to 62 GB in about six minutes. The kernel OOM killer
  killed `beam.smp` seven times on 2026-07-28 for exactly this, taking the
  editor down with it every time.
  """

  @runaway "Enum.flat_map(1..10, &Stream.cycle([&1]))"

  setup do
    heap = Application.get_env(:credence, :compile_max_heap_words)
    timeout = Application.get_env(:credence, :compile_timeout_ms)

    on_exit(fn ->
      restore(:compile_max_heap_words, heap)
      restore(:compile_timeout_ms, timeout)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:credence, key)
  defp restore(key, value), do: Application.put_env(:credence, key, value)

  describe "the bounds hold" do
    test "GREEN-0: ordinary source still compiles under the default bounds" do
      assert {:ok, _diagnostics} =
               RuleHelpers.compile_and_capture("defmodule CompileBoundsGreen0 do\nend\n")
    end

    test "source that never finishes allocating is contained, not fatal" do
      # Before the bound this call did not return — it grew until the kernel
      # killed the VM. The assertion that matters is as much that we get here
      # at all as it is the shape of the value.
      assert {:error, [diagnostic]} = RuleHelpers.compile_and_capture(@runaway)
      assert diagnostic.severity == :error
      assert diagnostic.message =~ "heap ceiling"

      # ...and the VM is still usable afterwards, which is the whole point.
      assert {:ok, _} = RuleHelpers.compile_and_capture("defmodule CompileBoundsAfter do\nend\n")
    end

    test "compiles?/1 reports an aborted compile as not compiling" do
      refute RuleHelpers.compiles?(@runaway)
    end

    test "a top-level exit/1 kills the child, not the caller" do
      assert {:error, [diagnostic]} = RuleHelpers.compile_and_capture("exit(:boom)")
      assert diagnostic.message =~ "exited during compilation"
      assert Process.alive?(self())
    end

    test "processes spawned by top-level source are killed before returning" do
      name = :credence_compile_bounds_spawned_child

      source =
        "spawn(fn -> Process.register(self(), #{inspect(name)}); Process.sleep(:infinity) end)"

      for _ <- 1..10 do
        assert {:ok, []} = RuleHelpers.compile_and_capture(source)
        assert Process.whereis(name) == nil
      end
    end
  end

  describe "module cleanup follows the compiler lifecycle" do
    test "minimized sequence: a raised compile cannot hide a later undefined-module diagnostic" do
      declared = Credence.CompileCleanupRaisedDeclaredFixture
      dynamic = Credence.CompileCleanupRaisedDynamicFixture
      isolate_modules([declared, dynamic])

      source = """
      defmodule Credence.CompileCleanupRaisedDeclaredFixture do
        def marker, do: :declared
      end

      Module.create(
        String.to_atom("Elixir.Credence.CompileCleanupRaisedDynamicFixture"),
        quote do
          def marker, do: :dynamic
        end,
        Macro.Env.location(__ENV__)
      )

      Credence.CompileCleanupMissingFixture.run()
      """

      assert {:error, _diagnostics} = RuleHelpers.compile_and_capture(source)
      refute Code.ensure_loaded?(declared)
      refute Code.ensure_loaded?(dynamic)

      probe = """
      defmodule Credence.CompileCleanupRaisedProbe do
        def declared, do: Credence.CompileCleanupRaisedDeclaredFixture.marker()
        def dynamic, do: Credence.CompileCleanupRaisedDynamicFixture.marker()
      end
      """

      assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(probe)

      for name <- [
            "Credence.CompileCleanupRaisedDeclaredFixture.marker/0 is undefined",
            "Credence.CompileCleanupRaisedDynamicFixture.marker/0 is undefined"
          ] do
        assert Enum.any?(diagnostics, &(&1.message =~ name))
      end
    end

    test "an aborted compile cleans declared and dynamically created modules" do
      declared = Credence.CompileCleanupAbortedDeclaredFixture
      dynamic = Credence.CompileCleanupAbortedDynamicFixture
      isolate_modules([declared, dynamic])

      source = """
      defmodule Credence.CompileCleanupAbortedDeclaredFixture do
        def marker, do: :declared
      end

      Module.create(
        String.to_atom("Elixir.Credence.CompileCleanupAbortedDynamicFixture"),
        quote do
          def marker, do: :dynamic
        end,
        Macro.Env.location(__ENV__)
      )

      exit(:after_modules_loaded)
      """

      assert {:error, [diagnostic]} = RuleHelpers.compile_and_capture(source)
      assert diagnostic.message =~ "exited during compilation"
      refute Code.ensure_loaded?(declared)
      refute Code.ensure_loaded?(dynamic)
    end

    test "an aborted compile cleans a declared module on the ordinary fast path" do
      declared = Credence.CompileCleanupFastPathFixture
      isolate_modules([declared])

      source = """
      defmodule Credence.CompileCleanupFastPathFixture do
        def marker, do: :declared
      end

      exit(:after_declared_module_loaded)
      """

      assert {:error, [diagnostic]} = RuleHelpers.compile_and_capture(source)
      assert diagnostic.message =~ "exited during compilation"
      refute Code.ensure_loaded?(declared)
    end

    test "a successful compile cleans a dynamically created module" do
      dynamic = Credence.CompileCleanupSuccessfulDynamicFixture
      isolate_modules([dynamic])

      source = """
      Module.create(
        String.to_atom("Elixir.Credence.CompileCleanupSuccessfulDynamicFixture"),
        quote do
          def marker, do: :dynamic
        end,
        Macro.Env.location(__ENV__)
      )
      """

      assert {:ok, []} = RuleHelpers.compile_and_capture(source)
      refute Code.ensure_loaded?(dynamic)
    end
  end

  # Positive controls. A ceiling nobody has seen enforced is a ceiling nobody
  # has verified — each of these perturbs one bound and requires that source
  # which passes comfortably under the real bound is refused under the tiny one.
  describe "the bounds are load-bearing (positive controls)" do
    test "CONTROL: the heap ceiling is consulted" do
      ordinary = "defmodule CompileBoundsHeapControl do\n  def a, do: 1\nend\n"
      assert {:ok, _} = RuleHelpers.compile_and_capture(ordinary)

      # One word of heap: nothing can compile under this.
      Application.put_env(:credence, :compile_max_heap_words, 1_000)

      assert {:error, [diagnostic]} = RuleHelpers.compile_and_capture(ordinary)
      assert diagnostic.message =~ "heap ceiling"
    end

    test "CONTROL: the deadline is consulted" do
      ordinary = "defmodule CompileBoundsTimeControl do\n  def a, do: 1\nend\n"
      assert {:ok, _} = RuleHelpers.compile_and_capture(ordinary)

      Application.put_env(:credence, :compile_timeout_ms, 1)

      assert {:error, [diagnostic]} = RuleHelpers.compile_and_capture(ordinary)
      assert diagnostic.message =~ "time budget"
    end
  end

  defp isolate_modules(modules) do
    Enum.each(modules, &unload/1)
    on_exit(fn -> Enum.each(modules, &unload/1) end)
  end

  defp unload(module) do
    :code.soft_purge(module)
    :code.delete(module)
    :code.soft_purge(module)
  end
end
