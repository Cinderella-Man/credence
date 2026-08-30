defmodule Credence.Semantic.FixHallucinatedMapPutArityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedMapPutArity

  @put5_message "Map.put/5 is undefined or private. Did you mean:\n\n    * put/3\n"
  @put7_message "Map.put/7 is undefined or private. Did you mean:\n\n    * put/3\n"
  @put2_message "Map.put/2 is undefined or private. Did you mean:\n\n    * put/3\n"

  defp fix(source, message, position) do
    FixHallucinatedMapPutArity.fix(source, %{
      severity: :warning,
      message: message,
      position: position
    })
  end

  test "fixes Map.put/5 by chaining into nested Map.put/3 calls" do
    input = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :type, :missing_required, :path, [:a])
      end
    end
    """

    expected = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(Map.put(%{}, :type, :missing_required), :path, [:a])
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {3, 9}), expected)
  end

  test "fixes Map.put/7 by chaining into three nested Map.put/3 calls" do
    input = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :a, 1, :b, 2, :c, 3)
      end
    end
    """

    expected = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(Map.put(Map.put(%{}, :a, 1), :b, 2), :c, 3)
      end
    end
    """

    confirm_fix(fix(input, @put7_message, {3, 9}), expected)
  end

  test "fixes Map.put/5 with variable map" do
    input = """
    defmodule HallucinatedMapPut do
      def build(map) do
        Map.put(map, :type, :missing_required, :path, [:a])
      end
    end
    """

    expected = """
    defmodule HallucinatedMapPut do
      def build(map) do
        Map.put(Map.put(map, :type, :missing_required), :path, [:a])
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {3, 9}), expected)
  end

  test "fixes Map.put/2 with map literal to Map.merge/2" do
    input = """
    defmodule FixMapPutArity2 do
      def update_state(state) do
        new_state = Map.put(state, %{status: :suspended, reason: "payment_failed"})
        new_state
      end
    end
    """

    expected = """
    defmodule FixMapPutArity2 do
      def update_state(state) do
        new_state = Map.merge(state, %{status: :suspended, reason: "payment_failed"})
        new_state
      end
    end
    """

    confirm_fix(fix(input, @put2_message, {3, 21}), expected)
  end

  test "fixes only the flagged call, other lines survive byte-for-byte" do
    input = """
    defmodule TwoCalls do
      def a(state) do
        Map.put(state, %{x: 1})
      end

      def b(m) do
        Map.put(m, :a, 1, :b, 2)
      end
    end
    """

    expected = """
    defmodule TwoCalls do
      def a(state) do
        Map.put(state, %{x: 1})
      end

      def b(m) do
        Map.put(Map.put(m, :a, 1), :b, 2)
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {7, 9}), expected)
  end

  test "fixes a lone candidate when the diagnostic has no column" do
    input = """
    defmodule NoColumn do
      def build(m) do
        Map.put(m, :a, 1, :b, 2)
      end
    end
    """

    expected = """
    defmodule NoColumn do
      def build(m) do
        Map.put(Map.put(m, :a, 1), :b, 2)
      end
    end
    """

    confirm_fix(fix(input, @put5_message, 3), expected)
  end

  test "leaves Map.put/3 unchanged" do
    input = """
    defmodule CleanExample do
      def build do
        Map.put(%{}, :key, :value)
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {3, 9}), input)
  end

  test "does not rewrite Map.put/2 with non-map second arg" do
    input = """
    defmodule CleanExample do
      def build(m, k) do
        Map.put(m, k)
      end
    end
    """

    confirm_fix(fix(input, @put2_message, {3, 9}), input)
  end

  test "does not rewrite the piped form" do
    input = """
    defmodule Piped do
      def build(m) do
        m |> Map.put(:a, 1, :b, 2)
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {3, 14}), input)
  end

  test "does not rewrite the capture form" do
    input = """
    defmodule Captured do
      def build do
        &Map.put/5
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {3, 10}), input)
  end

  test "does not rewrite a call at a different column than flagged" do
    input = """
    defmodule WrongColumn do
      def build(m) do
        Map.put(m, :a, 1, :b, 2)
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {3, 20}), input)
  end

  test "does not touch an aliased Map elsewhere when fixing the flagged line" do
    input = """
    defmodule Shadowed do
      def a(state) do
        alias Legacy.Map
        Map.put(state, %{x: 1})
      end

      def b(m) do
        Map.put(m, :a, 1, :b, 2)
      end
    end
    """

    expected = """
    defmodule Shadowed do
      def a(state) do
        alias Legacy.Map
        Map.put(state, %{x: 1})
      end

      def b(m) do
        Map.put(Map.put(m, :a, 1), :b, 2)
      end
    end
    """

    confirm_fix(fix(input, @put5_message, {8, 9}), expected)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @put5_message, {1, 1}), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :type, :missing_required, :path, [:a])
      end
    end
    """

    assert valid_syntax?(fix(input, @put5_message, {3, 9}))
  end

  test "end-to-end: Map.put/5 is fixed from real compiler diagnostics" do
    input = """
    defmodule CredenceMapPutArityE2E do
      def build(m) do
        Map.put(m, :type, :missing_required, :path, [:a])
      end
    end
    """

    expected = """
    defmodule CredenceMapPutArityE2E do
      def build(m) do
        Map.put(Map.put(m, :type, :missing_required), :path, [:a])
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: Map.put/2 with map literal is fixed from real compiler diagnostics" do
    input = """
    defmodule CredenceMapPutArityMergeE2E do
      def update_state(state) do
        Map.put(state, %{status: :suspended, reason: "payment_failed"})
      end
    end
    """

    expected = """
    defmodule CredenceMapPutArityMergeE2E do
      def update_state(state) do
        Map.merge(state, %{status: :suspended, reason: "payment_failed"})
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on one line are both fixed via their own columns" do
    input = """
    defmodule CredenceMapPutArityTwoOnLineE2E do
      def a(m), do: {Map.put(m, :a, 1, :b, 2), Map.put(m, :c, 3, :d, 4)}
    end
    """

    expected = """
    defmodule CredenceMapPutArityTwoOnLineE2E do
      def a(m), do: {Map.put(Map.put(m, :a, 1), :b, 2), Map.put(Map.put(m, :c, 3), :d, 4)}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the multi-line call form" do
    input = """
    defmodule CredenceMapPutArityMultilineE2E do
      def a(m) do
        Map.put(
          m,
          :a,
          1,
          :b,
          2
        )
      end
    end
    """

    expected = """
    defmodule CredenceMapPutArityMultilineE2E do
      def a(m) do
        Map.put(
          Map.put(
            m,
            :a,
            1
          ),
          :b,
          2
        )
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a Map.put spelling that resolves elsewhere via alias is left untouched" do
    input = """
    defmodule CredenceMapPutArityAliasShadowE2E do
      def a(m) do
        Map.put(m, :type, :missing_required, :path, [:a])
      end

      def b(state) do
        alias CredenceMapPutArityAliasShadowE2E.Legacy, as: Map
        Map.put(state, %{x: 1})
      end
    end
    """

    expected = """
    defmodule CredenceMapPutArityAliasShadowE2E do
      def a(m) do
        Map.put(Map.put(m, :type, :missing_required), :path, [:a])
      end

      def b(state) do
        alias CredenceMapPutArityAliasShadowE2E.Legacy, as: Map
        Map.put(state, %{x: 1})
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the capture form is deliberately left unfixed" do
    input = """
    defmodule CredenceMapPutArityCaptureE2E do
      def a, do: &Map.put/5
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: the piped form is deliberately left unfixed" do
    input = """
    defmodule CredenceMapPutArityPipeE2E do
      def a(m), do: m |> Map.put(:a, 1, :b, 2)
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end
end
