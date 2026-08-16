defmodule Credence.Semantic.FixTruncatedSpecialForm do
  @moduledoc """
  Fixes truncated Elixir special-form references (`__MODULE`, `__ENV`, `__DIR`,
  `__CALLER`, `__STACKTRACE`) that are missing the trailing `__`.

  LLMs frequently produce `__MODULE` instead of `__MODULE__`. The compiler
  treats the truncated form as a regular (undefined) variable and emits:

      undefined variable "__MODULE"

  This rule matches that diagnostic for any of the five `__X__` special forms
  and appends the missing `__` **at the diagnostic's `{line, col}` position
  only**, after verifying the truncated name is literally there.

  ## Matching vs fixing

  `match?/1` sees only the diagnostic (no source), so it claims every
  `undefined variable "__MODULE"`-shaped error; `fix/2` then verifies the
  source actually shows the truncated name at the reported column and no-ops
  otherwise, and the `should_report?/2` phase hook keeps `analyze` honest by
  reporting an issue only when the fix would rewrite the source.

  ## Deliberately skipped (no fix)

  - Any occurrence of the truncated text that did **not** produce the
    diagnostic: strings (`"__MODULE"`), comments, atoms (`:__MODULE`), and
    bound variables (`__MODULE = 5` is a legal variable binding) never emit
    `undefined variable`, and the position-scoped splice never touches them.
    A whole-file replace would corrupt exactly these.
  - Other misspellings (`__MODULE_`, `__MODULEX`, `foo__MODULE`, lowercase
    variants): their diagnostics carry a different variable name that is not
    in the known list, so the rule never claims them.
  - Diagnostics without a `{line, col}` position, or whose column does not
    sit on the truncated name (e.g. stale positions): splicing blind would
    corrupt the line, so the fix returns the source unchanged.

  Note `__CALLER`/`__STACKTRACE` are rewritten even when the canonical form is
  itself only legal in certain contexts (defmacro / rescue+catch): the input
  never compiled either way, and the fixed form surfaces the compiler's real,
  more precise contextual error instead of a bogus undefined-variable one.

  ## Priority

  `fix_case_branch_assignment_scope` claims the whole `undefined variable
  "name"` family at priority 500 (and its name regex admits `__MODULE`). The
  five truncated dunder names are claimed here at priority 450: an LLM
  emitting a bare `__MODULE` means the special form, not a case-scoped
  variable — same precedent as `fix_reraise_keyword_in_catch`.

  ## Why this rule beats `FixCaseBranchAssignmentScope`

  `FixCaseBranchAssignmentScope` admits every identifier in `undefined
  variable "name"`, `__MODULE` among them; this rule admits only the five
  dunder names and declares `priority: 450` against that rule's default 500,
  so the ordering is declared rather than inherited from where the module
  names sort (docs/20 §1). That rule's one repair hoists a `case` whose every
  branch ends in `__MODULE = value`, so on `def name, do: __MODULE` it finds
  no such `case` and returns the source unchanged — it cannot append the
  `__`. A declining rule now yields the slot (`first_effective_fix/3`), so
  what the ordering buys is that the rule which can splice runs first and is
  the one `analyze/2` attributes the issue to.

  ## Bad

      defmodule EnvTestFTSF do
        defmacro get_env, do: __ENV
      end

  ## Good

      defmodule EnvTestFTSF do
        defmacro get_env, do: __ENV__
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @dunder_names ~w(__MODULE __ENV __DIR __CALLER __STACKTRACE)

  @impl true
  def priority, do: 450

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    truncated_name(msg) != nil
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source, so unfixable sites (missing or
  stale positions) are not attributed to this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_truncated_special_form,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {line_num, col}})
      when is_integer(line_num) and line_num > 0 and is_integer(col) and col > 0 do
    lines = String.split(source, "\n")

    # Compiler columns are grapheme-aligned (verified against combining
    # accents and multi-codepoint emoji), so String.slice indexes match.
    with target when is_binary(target) <- truncated_name(msg),
         line_str when is_binary(line_str) <- Enum.at(lines, line_num - 1),
         width = String.length(target),
         ^target <- String.slice(line_str, col - 1, width),
         false <- identifier_continues?(line_str, col - 1 + width) do
      before_tok = String.slice(line_str, 0, col - 1)
      after_tok = String.slice(line_str, col - 1 + width, String.length(line_str))
      new_line = before_tok <> target <> "__" <> after_tok
      fixed = lines |> List.replace_at(line_num - 1, new_line) |> Enum.join("\n")

      case Sourceror.parse_string(fixed) do
        {:ok, _} -> fixed
        _ -> source
      end
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  defp truncated_name(msg) do
    case Regex.run(~r/^undefined variable "(__[A-Z_]+)"$/, msg) do
      [_, name] -> if name in @dunder_names, do: name, else: nil
      _ -> nil
    end
  end

  # True when the character at 0-based grapheme index `idx` would extend the
  # identifier (so the reported name cannot actually end at `idx` and the
  # position must be stale).
  defp identifier_continues?(line_str, idx) do
    String.match?(String.slice(line_str, idx, 1), ~r/^[A-Za-z0-9_?!]$/)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
