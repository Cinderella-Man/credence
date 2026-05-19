defmodule Credence.Pattern.Rule do
  @moduledoc """
  Behaviour for pattern-level rules that detect and auto-fix anti-patterns.

  Every Pattern rule fixes the issue it detects — there is no "warn-only"
  mode. Rules that could only detect but not fix were archived to
  `docs/unfixable_rules/` and removed from compilation.

  ## Fix interface

  Two callbacks express a fix, and rules can use either:

  - **`fix_patches(ast, opts) :: [patch]`** — preferred. Emit byte-range
    patches against the source. Only the changed bytes move; everything
    else stays byte-identical. Layout is preserved by construction.
    See `Credence.Pattern.NoListToTupleForAccess` for an example.

  - **`fix(source, opts) :: String.t()`** — adapter shape. Returns a
    transformed source string. The default `fix_patches/2` (provided by
    `__using__`) wraps `fix/2` in a single whole-source patch. Adequate
    when the rule's existing logic is source-level and refactoring into
    per-site patches would be substantially more work than the locality
    gain.
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
  Auto-fix returning the transformed source string. The default
  `fix_patches/2` wraps this in a whole-source patch.
  """
  @callback fix(source :: String.t(), opts :: keyword()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Pattern.Rule
      alias Credence.Issue

      @impl true
      def priority, do: 500

      @impl true
      def fix(source, _opts), do: source

      # Default `fix_patches/2`: emits a single whole-source patch
      # that delegates to the rule's `fix/2`. Lets every rule satisfy
      # the new patch-based interface without per-rule code changes.
      #
      # Rules that want real locality (one patch per match site, not a
      # whole-source rewrite) should override `fix_patches/2` directly
      # and ignore `fix/2`. See `NoListToTupleForAccess` for an example.
      @impl true
      def fix_patches(_ast, opts) do
        source = Keyword.fetch!(opts, :source)
        Credence.RuleHelpers.whole_source_patches(source, fix(source, opts))
      end

      defoverridable priority: 0, fix: 2, fix_patches: 2
    end
  end
end
