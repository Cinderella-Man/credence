defmodule Credence.Pattern.Rule do
  @moduledoc """
  Behaviour for pattern-level rules that detect and auto-fix anti-patterns.

  Every Pattern rule fixes the issue it detects — there is no "warn-only"
  mode. Rules that could only detect but not fix were archived to
  `docs/unfixable_rules/` and removed from compilation.

  ## Interface

  Every rule implements two callbacks:

  - **`check(ast, opts) :: [Issue.t()]`** — detect issues in the AST.
  - **`fix_patches(ast, opts) :: [patch]`** — emit byte-range patches
    that, when applied, resolve the issues `check/2` reported. Empty
    list = no change.

  Rules typically take one of two shapes:

  - **AST-walking** — walk the AST, locate target nodes, emit
    `%{range, change}` patches directly. See
    `Credence.Pattern.NoListToTupleForAccess` for an example.

  - **Source-level adapter** — when the transformation logic is
    naturally source-level (regex on lines, byte-range surgery), keep
    that logic in a private `legacy_fix/2` and delegate `fix_patches/2`
    to `Credence.RuleHelpers.patches_from_legacy_fix/3`. The adapter
    parses the post-fix source and AST-diffs against the original to
    emit one patch per outermost changed subtree (falling back to a
    whole-source patch when AST round-tripping is lossy).
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

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Pattern.Rule
      alias Credence.Issue

      @impl true
      def priority, do: 500

      defoverridable priority: 0
    end
  end
end
