defmodule Credence.Semantic.NoHallucinatedDefpstructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedDefpstruct

  @message "undefined function defpstruct/2 (there is no such import)"

  defp fix(source, message, line \\ 2) do
    NoHallucinatedDefpstruct.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces defpstruct with defstruct and @type, rewrites %Node{} to %__MODULE__{}" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        @type t :: %__MODULE__{
                key: {integer, integer},
                max_finish: integer,
                left: t | nil,
                right: t | nil,
                height: integer,
                count: integer
              }
        defstruct [:key, :max_finish, :left, :right, :height, :count]
      end

      def new, do: %Node{key: {1, 2}, max_finish: 2, left: nil, right: nil, height: 1, count: 1}
    end
    """

    expected = ~S"""
    defmodule FixTest do
      defstruct [:key, :max_finish, :left, :right, :height, :count]

      @type t :: %__MODULE__{
              key: {integer, integer},
              max_finish: integer,
              left: t | nil,
              right: t | nil,
              height: integer,
              count: integer
            }

      def new, do: %__MODULE__{key: {1, 2}, max_finish: 2, left: nil, right: nil, height: 1, count: 1}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        @type t :: %__MODULE__{
                key: {integer, integer},
                max_finish: integer,
                left: t | nil,
                right: t | nil,
                height: integer,
                count: integer
              }
        defstruct [:key, :max_finish, :left, :right, :height, :count]
      end

      def new, do: %Node{key: {1, 2}, max_finish: 2, left: nil, right: nil, height: 1, count: 1}
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no defpstruct pattern" do
    input = ~S"""
    defmodule Factory do
      defstruct [:name, :email]

      def build do
        %__MODULE__{name: "test", email: "test@example.com"}
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated error message" do
    input = ~S"""
    defmodule Example do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "unrelated error")
    confirm_fix(result, input)
  end

  test "rewrites multiple %Node{} references" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        defstruct [:key, :value]
      end

      def new(key, value), do: %Node{key: key, value: value}
      def update(node, value), do: %Node{key: node.key, value: value}
    end
    """

    expected = ~S"""
    defmodule FixTest do
      defstruct [:key, :value]

      def new(key, value), do: %__MODULE__{key: key, value: value}
      def update(node, value), do: %__MODULE__{key: node.key, value: value}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "block repair preserves non-code and references in sibling modules" do
    input = ~S'''
    defmodule BlockOwner do
      defpstruct Node do
        defstruct [:x]
      end

      # keep example %Node{x: 1}
      def text, do: "%Node{x: 2}"
      def docs, do: """
      keep %Node{x: 3}
      """
      def local, do: %Node{x: 4}
    end

    defmodule Node do
      defstruct [:x]
    end

    defmodule StructConsumer do
      def external, do: %Node{x: 5}
    end
    '''

    expected = ~S'''
    defmodule BlockOwner do
      defstruct [:x]

      # keep example %Node{x: 1}
      def text, do: "%Node{x: 2}"
      def docs, do: """
      keep %Node{x: 3}
      """
      def local, do: %__MODULE__{x: 4}
    end

    defmodule Node do
      defstruct [:x]
    end

    defmodule StructConsumer do
      def external, do: %Node{x: 5}
    end
    '''

    confirm_fix(fix(input, @message), expected)
  end

  test "repairs the block call on the diagnostic line" do
    input = ~S"""
    defmodule MultipleBlocks do
      defpstruct First do
        defstruct [:a]
      end
      defpstruct Second do
        defstruct [:b]
      end
    end
    """

    expected = ~S"""
    defmodule MultipleBlocks do
      defpstruct First do
        defstruct [:a]
      end
      defstruct [:b]
    end
    """

    confirm_fix(fix(input, @message, 5), expected)
  end

  # The line-based transform only reproduces one shape faithfully (single-line
  # defstruct optionally preceded by a single @type, nothing else). The
  # following shapes are deliberately left untouched: transforming them would
  # drop, reorder, or truncate code into a wrong or invalid result, so the rule
  # bails and leaves the compile error for a human.

  test "no-op: @type appears after defstruct (would be silently dropped)" do
    input = ~S"""
    defmodule M do
      defpstruct Node do
        defstruct [:key, :value]
        @type t :: %__MODULE__{key: any, value: any}
      end

      def new, do: %Node{key: 1, value: 2}
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op: multi-line defstruct (would be truncated to invalid source)" do
    input = ~S"""
    defmodule M do
      defpstruct Node do
        defstruct [
          :key,
          :value
        ]
      end

      def new, do: %Node{key: 1, value: 2}
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op: extra attribute in block (@enforce_keys would be reordered/broken)" do
    input = ~S"""
    defmodule M do
      defpstruct Node do
        @enforce_keys [:key]
        defstruct [:key, :value]
      end

      def new, do: %Node{key: 1, value: 2}
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "defpstruct without @type" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        defstruct [:key, :value]
      end

      def new, do: %Node{key: 1, value: 2}
    end
    """

    expected = ~S"""
    defmodule FixTest do
      defstruct [:key, :value]

      def new, do: %__MODULE__{key: 1, value: 2}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  # ════════════════════════════════════════════════════════════════
  # The `defpstructp` spelling and the keyword form — escalation ledger row 183.
  #
  # Row 183's repro is `defpstructp now: 0`. Two things were wrong with it and
  # only one was written down: the matcher's trailing `/` excluded the `p`
  # spelling, AND the fix only ever knew the block form, so even a matching
  # keyword-form diagnostic would have returned the source unchanged.
  # ════════════════════════════════════════════════════════════════

  @message_p "undefined function defpstructp/2 (there is no such import)"
  @message_kw "undefined function defpstruct/1 (there is no such import)"
  @message_p_kw "undefined function defpstructp/1 (there is no such import)"

  test "dissolves the block form under the defpstructp spelling" do
    input = ~S"""
    defmodule Blocky do
      defpstructp Inner do
        defstruct [:a]
      end
    end
    """

    expected = ~S"""
    defmodule Blocky do
      defstruct [:a]
    end
    """

    confirm_fix(fix(input, @message_p), expected)
  end

  test "renames the keyword form, both spellings" do
    for {input_name, message} <- [{"defpstruct", @message_kw}, {"defpstructp", @message_p_kw}] do
      input = """
      defmodule Kw do
        #{input_name} now: 0
      end
      """

      expected = """
      defmodule Kw do
        defstruct now: 0
      end
      """

      confirm_fix(fix(input, message), expected)
    end
  end

  # The rewrite patches the identifier's own byte range. A same-spelled word in
  # a comment or a string literal on the same line is therefore out of range by
  # construction, not by a guard that has to remember to exclude it — which is
  # the shape that has bitten five other rules in this tree.
  test "rewrites only the identifier, never a matching word in a comment or string" do
    input = ~S"""
    defmodule Scoped do
      defpstructp now: 0  # defpstructp is not real
      def doc, do: "use defpstructp here"
    end
    """

    expected = ~S"""
    defmodule Scoped do
      defstruct now: 0  # defpstructp is not real
      def doc, do: "use defpstructp here"
    end
    """

    confirm_fix(fix(input, @message_p_kw), expected)
  end

  test "declines when the module already defines a defstruct" do
    input = ~S"""
    defmodule Twice do
      defstruct [:a]
      defpstructp now: 0
    end
    """

    confirm_fix(fix(input, @message_p_kw), input)

    refute NoHallucinatedDefpstruct.should_report?(
             %{severity: :error, message: @message_p_kw},
             input
           )
  end

  test "a defstruct in a sibling module does not suppress keyword repair" do
    input = ~S"""
    defmodule AlreadyValid do
      defstruct [:ok]
    end

    defmodule BrokenKeyword do
      defpstruct nope: 0
    end
    """

    expected = ~S"""
    defmodule AlreadyValid do
      defstruct [:ok]
    end

    defmodule BrokenKeyword do
      defstruct nope: 0
    end
    """

    confirm_fix(fix(input, @message_kw, 6), expected)
  end

  test "the repaired keyword form compiles" do
    input = ~S"""
    defmodule Compiles do
      defpstructp now: 0
    end
    """

    fixed = fix(input, @message_p_kw)
    assert valid_syntax?(fixed)
    assert match?({:ok, _}, Credence.RuleHelpers.compile_and_capture(fixed))
  end
end
