defmodule Credence.Pattern.PreferMapNewWithTransformFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNewWithTransform

  test "rewrites Enum.map |> Map.new pipe pattern" do
    input = "Enum.map(1..5, fn i -> {i, i * i} end) |> Map.new()"

    expected = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "rewrites multi-line pipe pattern" do
    input = """
    1..5
    |> Enum.map(fn i -> {i, i * i} end)
    |> Map.new()
    """

    expected = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "rewrites nested Map.new(Enum.map(...)) pattern" do
    input = "Map.new(Enum.map(1..5, fn i -> {i, i * i} end))"

    expected = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "preserves surrounding code" do
    input = """
    defmodule Example do
      def build_map do
        1..5
        |> Enum.map(fn i -> {i, i * i} end)
        |> Map.new()
      end
    end
    """

    expected = """
    defmodule Example do
      def build_map do
        Map.new(1..5, fn i -> {i, i * i} end)
      end
    end
    """

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "does not change code without the pattern" do
    code = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  test "does not change Enum.map alone" do
    code = "Enum.map(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  test "does not change Map.new/1 alone" do
    code = "Map.new(1..5)"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  # Head-of-pipe 1-arg Enum.map has no collection to recover, so the fix is a
  # no-op — and the check is narrowed to not flag it, keeping the two in agreement.
  test "does not change head-of-pipe 1-arg Enum.map" do
    code = "Enum.map(fn i -> {i, i} end) |> Map.new()"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  # ════════════════════════════════════════════════════════════════════════
  # UPSTREAM PIPELINE — the collection is produced by a pipeline BEFORE the
  # `Enum.map`. The upstream pipeline must be kept intact and the map step
  # folded into a piped `Map.new/2` (never pulled out — that drops the piped
  # input and yields a non-existent `Map.new/3`).
  # ════════════════════════════════════════════════════════════════════════

  describe "upstream pipeline (collection stays piped into Map.new/2)" do
    test "one upstream step" do
      input = "data |> prep() |> Enum.map(fn x -> {x, x} end) |> Map.new()"
      expected = "data |> prep() |> Map.new(fn x -> {x, x} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "two upstream steps" do
      input = "src |> a() |> b() |> Enum.map(fn x -> {x, x} end) |> Map.new()"
      expected = "src |> a() |> b() |> Map.new(fn x -> {x, x} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "three upstream steps" do
      input = "src |> a() |> b() |> c() |> Enum.map(fn x -> {x, x} end) |> Map.new()"
      expected = "src |> a() |> b() |> c() |> Map.new(fn x -> {x, x} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "upstream Enum.filter/2" do
      input =
        "list |> Enum.filter(fn x -> x > 0 end) |> Enum.map(fn x -> {x, x} end) |> Map.new()"

      expected = "list |> Enum.filter(fn x -> x > 0 end) |> Map.new(fn x -> {x, x} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "upstream Enum.reject/2" do
      input =
        "list |> Enum.reject(fn {k, _v} -> k in keys end) |> Enum.map(fn {k, v} -> {k, v} end) |> Map.new()"

      expected =
        "list |> Enum.reject(fn {k, _v} -> k in keys end) |> Map.new(fn {k, v} -> {k, v} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "upstream Enum.chunk_every/2 (the supavisor shape)" do
      input =
        "fields |> Enum.chunk_every(2) |> Enum.map(fn [k, v] -> {k, v} end) |> Map.new()"

      expected = "fields |> Enum.chunk_every(2) |> Map.new(fn [k, v] -> {k, v} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "upstream Enum.group_by/2" do
      input =
        "rows |> Enum.group_by(fn r -> r.id end) |> Enum.map(fn {id, rs} -> {id, length(rs)} end) |> Map.new()"

      expected =
        "rows |> Enum.group_by(fn r -> r.id end) |> Map.new(fn {id, rs} -> {id, length(rs)} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "upstream local call with an argument (the process_duplicates shape)" do
      input =
        "list |> process_duplicates(:keep) |> Enum.map(fn {k, v} -> {k, shortest(v)} end) |> Map.new()"

      expected =
        "list |> process_duplicates(:keep) |> Map.new(fn {k, v} -> {k, shortest(v)} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "preserves surrounding code with an upstream pipeline" do
      input = """
      defmodule Example do
        def build(list) do
          list
          |> filter_keys()
          |> Enum.map(fn {k, v} -> {k, f(v)} end)
          |> Map.new()
        end
      end
      """

      expected = """
      defmodule Example do
        def build(list) do
          list
          |> filter_keys()
          |> Map.new(fn {k, v} -> {k, f(v)} end)
        end
      end
      """

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # SINGLE PIPE HEAD that is itself a call — `before` is exactly one element
  # (a complete expression), so it inlines into `Map.new/2`'s first argument.
  # ════════════════════════════════════════════════════════════════════════

  describe "single call head is inlined as Map.new/2's first arg" do
    test "Enum.reject head (the delete_in shape)" do
      input =
        "Enum.reject(map, fn {k, _v} -> k in keys end) |> Enum.map(fn {k, v} -> {k, v} end) |> Map.new()"

      expected =
        "Map.new(Enum.reject(map, fn {k, _v} -> k in keys end), fn {k, v} -> {k, v} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "zero-arg function call head" do
      input = "build_list() |> Enum.map(fn x -> {x, x} end) |> Map.new()"
      expected = "Map.new(build_list(), fn x -> {x, x} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # TRAILING pipeline after Map.new (`after_` is non-empty).
  # ════════════════════════════════════════════════════════════════════════

  describe "trailing pipeline after Map.new" do
    test "single head, trailing step" do
      input = "1..5 |> Enum.map(fn i -> {i, i} end) |> Map.new() |> Enum.count()"
      expected = "Map.new(1..5, fn i -> {i, i} end) |> Enum.count()"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "upstream pipeline and trailing step" do
      input =
        "list |> prep() |> Enum.map(fn x -> {x, x} end) |> Map.new() |> Enum.to_list()"

      expected = "list |> prep() |> Map.new(fn x -> {x, x} end) |> Enum.to_list()"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # 2-ARG Enum.map (collection explicit) — unchanged behaviour.
  # ════════════════════════════════════════════════════════════════════════

  describe "2-arg Enum.map keeps inlining the explicit collection" do
    test "var collection" do
      input = "Enum.map(coll, fn x -> {x, x} end) |> Map.new()"
      expected = "Map.new(coll, fn x -> {x, x} end)"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end

    test "2-arg map with a trailing step" do
      input = "Enum.map(coll, fn x -> {x, x} end) |> Map.new() |> Enum.count()"
      expected = "Map.new(coll, fn x -> {x, x} end) |> Enum.count()"

      confirm_fix(fix(PreferMapNewWithTransform, input), expected)
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # IDEMPOTENCE — the fixed output no longer matches the pattern, so a second
  # pass is a no-op. (Guards against the fix re-firing on its own `Map.new/2`.)
  # ════════════════════════════════════════════════════════════════════════

  describe "idempotence" do
    test "single-head fix is idempotent" do
      once = fix(PreferMapNewWithTransform, "1..5 |> Enum.map(fn i -> {i, i} end) |> Map.new()")

      confirm_fix(fix(PreferMapNewWithTransform, once), once)
    end

    test "upstream-pipeline fix is idempotent" do
      once =
        fix(
          PreferMapNewWithTransform,
          "list |> prep() |> Enum.map(fn x -> {x, x} end) |> Map.new()"
        )

      confirm_fix(fix(PreferMapNewWithTransform, once), once)
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # Output validity — the fix must never emit a non-existent Map.new/3.
  # ════════════════════════════════════════════════════════════════════════

  describe "output is always a valid Map.new arity" do
    for {label, input} <- [
          {"upstream pipeline", "a |> b() |> Enum.map(fn x -> {x, x} end) |> Map.new()"},
          {"single call head", "f() |> Enum.map(fn x -> {x, x} end) |> Map.new()"},
          {"trailing step",
           "a |> b() |> Enum.map(fn x -> {x, x} end) |> Map.new() |> Enum.to_list()"}
        ] do
      test "no Map.new/3 for: #{label}" do
        fixed = fix(PreferMapNewWithTransform, unquote(input))
        # Every Map.new call in the result has arity 0, 1, or 2 — never 3.
        for {{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, args} <-
              fixed |> Code.string_to_quoted!() |> Macro.prewalk([], &{&1, [&1 | &2]}) |> elem(1),
            into: [] do
          assert length(args) <= 2, "emitted Map.new/#{length(args)} in: #{fixed}"
        end
      end
    end
  end
end
