defmodule Credence.Syntax.FixMixedRequiredOptionalMapKeysFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixMixedRequiredOptionalMapKeys

  defp analyze(code), do: FixMixedRequiredOptionalMapKeys.analyze(code)
  defp fix(code), do: FixMixedRequiredOptionalMapKeys.fix(code)

  describe "rewrites the keyword entry into arrow form" do
    test "the type field sample" do
      input = "@type t :: %{state: atom(), optional(atom()) => any()}"
      expected = "@type t :: %{:state => atom(), optional(atom()) => any()}"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    test "the literal field sample" do
      input = "x = %{state: :init, optional(k) => v}"
      expected = "x = %{:state => :init, optional(k) => v}"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    # Every key shape arrow-ifies, so none is excluded. `:"a b"` is the same atom as
    # the keyword key `"a b":`, executed: both inspect as `%{"a b": 1}`.
    test "a quoted key" do
      confirm_fix(fix(~S'x = %{"a b": 1, "k" => 2}'), ~S'x = %{:"a b" => 1, "k" => 2}')
      assert valid_syntax?(fix(~S'x = %{"a b": 1, "k" => 2}'))
    end

    test "a key ending in a question mark" do
      confirm_fix(fix(~S'x = %{valid?: 1, "k" => 2}'), ~S'x = %{:valid? => 1, "k" => 2}')
      assert valid_syntax?(fix(~S'x = %{valid?: 1, "k" => 2}'))
    end

    # The colon the rule rewrites is the KEY's. Keyword syntax forbids a space before
    # the colon, so the first colon at the entry's own bracket depth is always the
    # key's — never one belonging to the value.
    test "an atom value keeps its own colon" do
      confirm_fix(fix(~S'x = %{a: :b, "k" => 2}'), ~S'x = %{:a => :b, "k" => 2}')
    end

    test "a nested map value is left keyword form, because it is legal there" do
      confirm_fix(fix(~S'x = %{a: %{c: 1}, "k" => 2}'), ~S'x = %{:a => %{c: 1}, "k" => 2}')
      assert valid_syntax?(fix(~S'x = %{a: %{c: 1}, "k" => 2}'))
    end

    # The comma inside `f(1, 2)` is at a deeper bracket depth, so it is not mistaken
    # for the entry boundary.
    test "a call in the value" do
      confirm_fix(fix(~S'x = %{a: f(1, 2), "k" => 3}'), ~S'x = %{:a => f(1, 2), "k" => 3}')
    end

    test "an inner map is the culprit and the outer entry is untouched" do
      confirm_fix(fix(~S'x = %{ok: %{a: 1, "k" => 2}}'), ~S'x = %{ok: %{:a => 1, "k" => 2}}')
      assert valid_syntax?(fix(~S'x = %{ok: %{a: 1, "k" => 2}}'))
    end

    # The entry's leading whitespace is preserved byte for byte, which is what keeps a
    # multi-line map's newline and indentation intact.
    test "a multi-line map keeps its layout" do
      input = """
      x = %{
        a: 1,
        "k" => 2
      }
      """

      expected = """
      x = %{
        :a => 1,
        "k" => 2
      }
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end
  end

  # Every occurrence in ONE call, and that is required rather than tidy. The Syntax
  # round calls each `fix/1` exactly once and `commit_or_roll_back/4` then discards the
  # whole round if the result still does not parse, so a rule repairing one entry per
  # call would repair NOTHING on a map with two.
  describe "repairs every entry in one call" do
    test "two keyword entries in one map" do
      once = fix(~S'x = %{a: 1, b: 2, "k" => 3}')

      confirm_fix(once, ~S'x = %{:a => 1, :b => 2, "k" => 3}')
      assert valid_syntax?(once)
      assert analyze(once) == []
    end

    test "two separate maps in one file" do
      input = """
      defmodule Two do
        @type t :: %{a: 1, "k" => 2}
        def f, do: %{b: 2, "j" => 3}
      end
      """

      expected = """
      defmodule Two do
        @type t :: %{:a => 1, "k" => 2}
        def f, do: %{:b => 2, "j" => 3}
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "the whole round commits instead of rolling back" do
      input = """
      defmodule Two do
        @type t :: %{a: 1, "k" => 2}
        def f, do: %{b: 2, "j" => 3}
      end
      """

      {code, applied} = Credence.Syntax.fix_with_trace(input)

      assert applied == [{Credence.Syntax.FixMixedRequiredOptionalMapKeys, 1}]
      assert valid_syntax?(code)
      refute code == input
    end
  end

  describe "declines, byte for byte" do
    for {label, input} <- [
          {"source that parses", ~s|x = %{"k" => 2, a: 1}\n|},
          {"a map already in arrow form", ~s|x = %{:a => 1, "k" => 2}\n|},
          {"a list, where arrow form is not valid syntax", "x = [a: 1, 2]\n"},
          {"a tuple, where arrow form is not valid syntax", "x = {a: 1, 2}\n"},
          {"a call, which is the sibling rule's job", "f(a: 1, 2)\n"},
          {"a struct, where the repair would not fix the module", ~s|x = %Foo{a: 1, "k" => 2}\n|},
          {"a decoy in a string, with an unrelated parse error", ~s|x = "%{a: 1, 2}"\ny = (\n|},
          {"a decoy in a comment, with an unrelated parse error", "# %{a: 1, 2}\ny = (\n"},
          {"an unrelated syntax error", "x = foo((1\n"}
        ] do
      test label do
        input = unquote(input)
        confirm_fix(fix(input), input)
      end
    end
  end

  # Byte offsets on both sides of the edit. `mask/1` keeps the shadow the same number of
  # BYTES as the source, not graphemes, so a scan mixing the two goes inert on the first
  # file with a non-ASCII comment — measured on the sibling `when`-guard rule.
  describe "is not defeated by multi-byte characters" do
    for {label, prefix} <- [
          {"a flag emoji in a comment", "# 🇵🇱 note\n"},
          {"an accent in a string", ~s|y = "héllo"\n|}
        ] do
      test label do
        input = unquote(prefix) <> ~s|x = %{a: 1, "k" => 2}\n|
        expected = unquote(prefix) <> ~s|x = %{:a => 1, "k" => 2}\n|

        confirm_fix(fix(input), expected)
        assert valid_syntax?(fix(input))
      end
    end
  end

  # A rule keyed on a parse ERROR cannot touch a file that parses, and every source
  # file in the tree parses — so the byte-scope class the self-corruption oracle exists
  # to catch is structurally unreachable. Measured over all of `lib/**/*.ex`: 0 of 330
  # files altered.
  describe "cannot corrupt source that parses" do
    test "its own source is untouched" do
      own = File.read!("lib/syntax/fix_mixed_required_optional_map_keys.ex")

      confirm_fix(fix(own), own)
      assert analyze(own) == []
    end

    test "no file in lib/ is altered" do
      altered =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.filter(fn path ->
          source = File.read!(path)
          fix(source) != source
        end)

      assert altered == []
    end
  end
end
