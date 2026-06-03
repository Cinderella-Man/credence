defmodule Credence.Pattern.Rule do
  @moduledoc """
  Behaviour for pattern-level rules that detect and auto-fix anti-patterns.

  Every Pattern rule fixes the issue it detects — there is no "warn-only"
  mode. Rules that could only detect but not fix were archived to
  `docs/unfixable_rules/` and removed from compilation.

  ## Interface

  Three callbacks, all mandatory (only `priority/0` has a default):

  - **`priority() :: integer()`** — fire order, lower runs first. Default 500.
  - **`check(ast, opts) :: [Issue.t()]`** — detect issues in the AST.
  - **`fix_patches(ast, opts) :: [patch]`** — emit byte-range patches that,
    when applied, resolve the issues `check/2` reported. Empty list = no
    change.

  Both callbacks receive Sourceror AST (`Sourceror.parse_string!/1`) and
  `opts` containing `:source` for rules that need raw source bytes.

  ## Implementation choices for `fix_patches/2`

  All rules return `[patch]`, but the way they compute those patches
  varies with what the transformation needs:

  - **AST-walking** — `Credence.RuleHelpers.patches_from_postwalk/2`
    handles rules whose fix is a single `Macro.postwalk/2` matcher.
  - **AST-with-restructuring** —
    `Credence.RuleHelpers.patches_from_ast_transform/3` for fixes that
    prune, reorder, or insert siblings (the rendered result is re-parsed
    for clean range diffing).
  - **Direct patch emission** — a rule walks the AST itself and builds
    `[%{range: Sourceror.Range, change: String.t()}]` manually. Useful
    when the kept subtree's source bytes must be preserved verbatim
    (e.g. parens metadata Sourceror's renderer would drop) — slice the
    original source bytes for the kept range instead of re-rendering.

  See each helper's docstring for the rule-side calling convention.
  """

  @typedoc """
  A byte-range patch against the source string.

  - `range` carries Sourceror-style start/end positions (`[line: L, column: C]`).
  - `change` is the replacement text. Apply via `Sourceror.patch_string/2`.
  """
  @type patch :: %{
          required(:range) => map(),
          required(:change) => String.t()
        }

  @callback priority() :: integer()

  @doc "Detect issues in the AST. Returns list of issues."
  @callback check(ast :: Macro.t(), opts :: keyword()) :: [Credence.Issue.t()]

  @doc "Auto-fix via byte-range patches. Returns a list of patches; `[]` means no change."
  @callback fix_patches(ast :: Macro.t(), opts :: keyword()) :: [patch()]

  @doc """
  The assumptions (safety switches) this rule's fix relies on to be
  behaviour-preserving. Returns a list of switch names from
  `Credence.Assumptions`; `[]` (the default) means the fix is correct for
  *every* input and is never filtered out.

  A rule only runs when **all** of its named assumptions are currently on
  (see `Credence.RuleHelpers.filter_by_assumptions/3`). Defaults to `[]`.
  """
  @callback assumptions() :: [atom()]

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Pattern.Rule
      alias Credence.Issue

      @impl true
      def priority, do: 500

      @impl true
      def assumptions, do: []

      defoverridable priority: 0, assumptions: 0
    end
  end
end
