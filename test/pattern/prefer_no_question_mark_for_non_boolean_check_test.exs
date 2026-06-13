defmodule Credence.Pattern.PreferNoQuestionMarkForNonBooleanCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferNoQuestionMarkForNonBoolean

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — functions with ? suffix and non-boolean return type
  # ═══════════════════════════════════════════════════════════════════

  test "flags private function with ? suffix returning integer | nil" do
    assert flagged?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Solution do
             @spec find_max_integer?([any()]) :: integer() | nil
             defp find_max_integer?([]), do: nil

             defp find_max_integer?(list) when is_list(list) do
               if Enum.any?(list, fn element -> not is_integer(element) end) do
                 nil
               else
                 Enum.max(list)
               end
             end
           end
           """)
  end

  test "flags private function with ? suffix returning String.t()" do
    assert flagged?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec get_name?(atom()) :: String.t() | nil
             defp get_name?(:foo), do: "bar"
             defp get_name?(_), do: nil
           end
           """)
  end

  test "flags private function with ? suffix returning list()" do
    assert flagged?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec get_items?() :: list()
             defp get_items?, do: [1, 2, 3]
           end
           """)
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — functions that should NOT be flagged
  # ═══════════════════════════════════════════════════════════════════

  test "leaves boolean predicate alone" do
    assert clean?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec empty?([any()]) :: boolean()
             def empty?([]), do: true
             def empty?(_), do: false
           end
           """)
  end

  test "leaves function without ? suffix alone" do
    assert clean?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec find_max([any()]) :: integer() | nil
             def find_max([]), do: nil
             def find_max(list), do: Enum.max(list)
           end
           """)
  end

  test "leaves true | false return type alone" do
    assert clean?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec valid?(any()) :: true | false
             def valid?(_), do: true
           end
           """)
  end

  # Renaming a public function is a breaking API change (and can't reach
  # external callers / `@doc` / `c:Mod.fun?` references), so public `def`s with
  # a `?` suffix are left alone even when the @spec return type is non-boolean.
  test "leaves a public def with ? suffix alone" do
    assert clean?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec get_name?(atom()) :: String.t() | nil
             def get_name?(:foo), do: "bar"
             def get_name?(_), do: nil
           end
           """)
  end

  # A name with both public and private clauses is treated as public (skipped):
  # the rename would still break the public arity.
  test "leaves a name with both def and defp clauses alone" do
    assert clean?(PreferNoQuestionMarkForNonBoolean, """
           defmodule Example do
             @spec get_name?(atom()) :: String.t() | nil
             def get_name?(:foo), do: "bar"
             defp get_name?(_), do: nil
           end
           """)
  end
end
