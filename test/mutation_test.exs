defmodule Credence.MutationTest do
  use ExUnit.Case, async: true

  alias Credence.Mutation
  alias Credence.Mutation.Mutant

  @moduledoc """
  docs/22 T2.4 / docs/12 C18 — the mutant generator and its guards.

  A mutant is one byte-level edit to one token of a rule's source. The whole
  measurement rests on the edit landing where the tokenizer said it would, and on
  the baseline being green before anything is scored — so those two are what
  these pin, alongside the operator families themselves.
  """

  describe "the four operator families" do
    test "comparison_swap turns strict into non-strict and back" do
      source = "defmodule M do\n  def f(a, b), do: a >= b\nend\n"

      {:ok, mutants} = Mutation.mutants(source)

      mutated =
        mutants
        |> Enum.filter(&(&1.operator == :comparison_swap))
        |> Enum.map(&Mutation.apply_mutant(source, &1))

      assert Enum.any?(mutated, &(&1 =~ "a > b"))
    end

    test "off_by_one moves every integer literal both ways" do
      source = "defmodule M do\n  def f, do: 3\nend\n"

      {:ok, mutants} = Mutation.mutants(source)

      mutated =
        mutants
        |> Enum.filter(&(&1.operator == :off_by_one))
        |> Enum.map(&Mutation.apply_mutant(source, &1))

      assert Enum.any?(mutated, &(&1 =~ "do: 4"))
      assert Enum.any?(mutated, &(&1 =~ "do: 2"))
    end

    test "ok_error_swap inverts the matcher signal" do
      source = "defmodule M do\n  def f, do: :ok\nend\n"

      {:ok, mutants} = Mutation.mutants(source)

      mutated =
        mutants
        |> Enum.filter(&(&1.operator == :ok_error_swap))
        |> Enum.map(&Mutation.apply_mutant(source, &1))

      assert Enum.any?(mutated, &(&1 =~ ":error"))
    end

    test "boolean_flip flips a literal" do
      source = "defmodule M do\n  def f, do: true\nend\n"

      {:ok, mutants} = Mutation.mutants(source)

      mutated =
        mutants
        |> Enum.filter(&(&1.operator == :boolean_flip))
        |> Enum.map(&Mutation.apply_mutant(source, &1))

      assert Enum.any?(mutated, &(&1 =~ "do: false"))
    end
  end

  describe "what is deliberately not mutated" do
    # ~40% of the token budget on some rules, and every one of them an
    # equivalent mutant by construction: prose cannot change behaviour, so
    # mutating it would depress the kill rate for no reason and bury the real
    # survivors in the tail.
    test "a moduledoc's comparison operators are left alone" do
      source = """
      defmodule M do
        @moduledoc "flags a >= b but not a > b"
        def f(a, b), do: a == b
      end
      """

      {:ok, mutants} = Mutation.mutants(source)
      refute Enum.any?(mutants, &(&1.operator == :comparison_swap))
    end

    test "a comment's integers are left alone" do
      source = "defmodule M do\n  # bump to 3 later\n  def f, do: :ok\nend\n"

      {:ok, mutants} = Mutation.mutants(source)
      refute Enum.any?(mutants, &(&1.operator == :off_by_one))
    end

    test "a string's contents are left alone" do
      source = ~S|defmodule M do
  def f, do: "use >= here"
end
|

      {:ok, mutants} = Mutation.mutants(source)
      refute Enum.any?(mutants, &(&1.operator == :comparison_swap))
    end
  end

  # The control that matters most. Every score this task reports assumes the
  # edit landed on the token the tokenizer named. If columns and bytes ever
  # disagree, a mutant would silently corrupt a DIFFERENT token and still be
  # scored — inflating or deflating the kill rate with no way to notice.
  describe "CONTROL: a misaligned mutant raises rather than corrupting" do
    test "a mutant whose original does not match the source is refused" do
      source = "defmodule M do\n  def f(a, b), do: a >= b\nend\n"

      liar = %Mutant{
        id: "planted-1",
        operator: :comparison_swap,
        line: 2,
        column: 1,
        original: ">=",
        replacement: ">"
      }

      assert_raise ArgumentError, ~r/expected ">=" at 2:1/, fn ->
        Mutation.apply_mutant(source, liar)
      end
    end

    test "a mutant pointing past the end of the source is refused" do
      source = "defmodule M do\nend\n"

      liar = %Mutant{
        id: "planted-2",
        operator: :off_by_one,
        line: 99,
        column: 1,
        original: "1",
        replacement: "2"
      }

      assert_raise ArgumentError, ~r/past end of source/, fn ->
        Mutation.apply_mutant(source, liar)
      end
    end
  end

  describe "generation is deterministic" do
    # A reported sample is only reproducible if the generator is. Two runs over
    # the same source must produce the same mutants in the same order.
    test "the same source yields the same mutants twice" do
      source = "defmodule M do\n  def f(a, b), do: a >= b and 3 == 4\nend\n"

      {:ok, first} = Mutation.mutants(source)
      {:ok, second} = Mutation.mutants(source)

      assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)
    end

    test "the cap is honoured" do
      source =
        "defmodule M do\n" <>
          Enum.map_join(1..60, "\n", fn i -> "  def f#{i}, do: #{i}" end) <> "\nend\n"

      {:ok, mutants} = Mutation.mutants(source, cap: 5)
      assert length(mutants) == 5
    end
  end
end
