# Must-Read Scope and Focused Profile Interview

**Status:** Approved design

**Date:** 2026-10-07

## Summary

The long-term research profile determines which papers are relevant enough to
recommend. The optional must-read focus provides a second, finer decision
inside that recommendation set: whether a paper directly serves the specific
question, object, method, or goal that currently deserves priority.

Focused mode does not redefine general relevance. A paper that strongly
matches the long-term profile may still be `recommended` when it does not match
the current focus. It cannot become `must_read` unless it directly matches that
focus.

The guided profile interview therefore has two phases. It first establishes
the long-term research profile, then asks what `must_read` should mean. A
focused choice starts an adaptive interview that proposes concrete hypotheses
instead of requiring the user to formulate a precise research question from
scratch. A separate short flow lets an existing user update only the
must-read scope and focus.

This remains a paper-triage workflow. It does not become a project manager,
PDF reader, or feedback-learning system.

## Product rules

### Research-direction mode

- The existing research-profile prompt and score meanings are preserved.
- Strong matches to long-term interests, methods, or regions may receive
  `must_read`.
- No focused interview or focused explanation is required.

### Focused mode

- The long-term profile continues to determine general paper relevance and
  recommendation.
- The current focus refines only which otherwise relevant papers qualify for
  `must_read`.
- A direct focus match is necessary, but not sufficient, for `must_read`.
- A paper that does not directly match the focus cannot score above 89.
- A non-matching paper may still be `recommended` when it is highly relevant
  to the long-term research direction.
- Direct focus matching must not raise an otherwise low-value paper to
  `must_read`.
- Every focused-mode paper included in the report explains both its focus
  relationship and its overall research relevance.

There is no second numeric score. The LLM assesses general relevance from the
long-term profile and separately reports whether the paper directly matches
the must-read focus. The application combines those results when assigning the
final category.

## Goals

- Let the user explicitly choose a broad or focused meaning for `must_read`.
- Preserve current scoring behavior in research-direction mode.
- Keep general recommendation based on the long-term profile while refining
  `must_read` through an optional current focus.
- Reuse the existing interview rhythm while supporting single choice, multiple
  choice, free text, and selected options plus a free-text clarification.
- Explain how each question will improve recommendation behavior without
  exposing internal scoring rules.
- Store a concise, validated focus that can be applied consistently to paper
  titles and abstracts.
- Provide a short path for changing only the current scope/focus.
- Preserve old profiles and recommendation history without a forced migration.
- Keep historical focus decisions understandable after the active focus
  changes.
- Avoid requesting unnecessary identity or confidential project information.

## Non-goals

- Managing multiple named or concurrent projects.
- Learning preferences from clicks, reading behavior, PDF downloads, or
  Reader Review fields.
- Adding a second numeric relevance score or a deterministic weighted formula.
- Replacing the guided interview with a static form.
- Requiring project names, institutions, collaborators, funding information,
  unpublished results, or confidential identifiers.
- Re-scoring existing history when the focus changes.
- Adding PDF acquisition, full-text analysis, annotation, knowledge graphs, or
  literature-library management.

## Terminology

### Primary focus

The central scientific requirement used to judge whether a paper directly
helps the work that currently deserves attention. It may concern a question,
object, phenomenon, method, observation type, region, application, or intended
impact.

### Supporting signals

Methods, data types, phenomena, settings, regions, or applications that make a
direct match more convincing. They support the primary focus but do not replace
it and are not all independent hard requirements.

### Primary-focus-only mode

Some focuses are sufficiently precise without supporting signals. This is an
explicit user-confirmed state, not an empty value inferred from an incomplete
LLM response.

## Guided interview behavior

### Interview state

The state records:

- `phase`: `long_term`, `extend`, `scope`, `focused`, or `review`.
- Long-term answers, additional direction evidence, summary revisions, final
  summary, and question count.
- Selected `must_read_scope`.
- Focused answers, proposal revisions, final proposal, and question count.
- Interview language and tentative RSS-source context.

Long-term and focused counts are independent. The fixed scope question is not
counted as a focused LLM question.

Changing the long-term understanding after focus questions have begun clears
the scope choice, focused answers, and proposal, then returns to the scope
question. Changing the scope clears all focused state. Revising the previous
answer affects only the active phase and regenerates later inference from the
corrected history.

Cancel at any point discards the entire unsaved flow and leaves the current
profile unchanged.

### Question purpose and answer modes

Every question page displays a `Purpose` line before the current inference: one
sentence of at most 25 words, written after the question is chosen, that
explains how the answer will improve filtering without exposing scores or
numeric thresholds.

- Long-term phase purpose: clarify which papers belong in the user's general
  recommendation scope.
- Must-read phase purpose: clarify which already-relevant papers deserve the
  highest reading priority because they directly serve a current need.
- A more specific purpose may explain that the question is distinguishing
  research objects, methods, regions, applications, or supporting evidence.

An LLM-generated question uses this exact shape:

```json
{
  "action": "ask",
  "question_purpose": "One short user-facing sentence",
  "selection_mode": "single | multiple",
  "current_inference": "...",
  "question": "...",
  "options": ["...", "..."]
}
```

For `single`, the 2–4 options must be mutually exclusive. For `multiple`, they
must be distinct, compatible signals that may be combined. The CLI accepts:

- One option number, such as `2`.
- Multiple option numbers for a multiple-choice question, such as `1,3`.
- Free text without selecting an option.
- Selected options followed by a clarification, such as
  `1,3，同时关注海啸磁场`.

The stored interview answer retains both the resolved option texts and the
free-text clarification. The LLM must not add a generic Other option.

Number lists accept commas, whitespace, and the conjunctions `和`, `と`, and
the English word `and` between numbers. A single-choice question still rejects
more than one selection. The CLI answer prompt states the accepted count
(`one number` for single, `one or more numbers` for multiple), so no separate
answer-mode label is displayed. The opening keyword question has no options;
its `selection_mode` value is ignored and only free text is accepted.

### Phase 1: long-term profile

The existing one-question-at-a-time interview continues to build the long-term
research profile. The phase introduction tells the user that these questions
determine which papers are relevant enough to recommend.

Phase-1 questions form a funnel that visibly narrows toward concrete research
content:

- The funnel starts from the user's own keywords and then descends one
  granularity level at a time: (1) the user's keywords for their target
  research area, (2) sub-directions, problem classes, or aspects within those
  keywords, (3) specific topics, systems, phenomena, or objects.
- The profile's finest level is level 3, and the funnel descends along the
  research subject rather than the methodology. Methods, algorithms, model
  families, tools, theoretical guarantees, and individual datasets stay beyond
  this phase, because they are not needed to judge whether a paper belongs to
  the research direction. Once level 3 is clear, the interview summarizes
  instead of drilling deeper.
- A level is clear when the user's answers name at least one concrete item at
  that level and the latest answer introduces no new unresolved branch. While a
  level is ambiguous, the interview asks another question at the same level
  about a different facet. Once a level is clear, it descends exactly one
  level.
- From the second question onward, the question, its current inference, and its
  options stay at one level, as peers of the same granularity.
- When an answer contains several keywords or selections, the interview treats
  every one of them as active — a conjunction rather than an either-or. When
  they span different branches, it asks one question covering all of them or
  first asks which is the primary line.
- When the latest answer is meta, evasive, or names no concrete item, the next
  question requests concrete content at the current level, such as 2–3
  keywords or a brief description. The CLI supplies free-text entry.
- The first question asks for the user's target research area as one or more
  free-text keywords. It has no options: the model returns an empty options
  list and puts 1–2 brief examples inside the question text instead of a
  predefined field list.

When enabled RSS sources exist, the first question instead uses the journal
names and URLs as a tentative scope clue: it offers 2–4 candidate keywords
derived from that scope as options, which the user may select, combine, or
replace with their own keywords. Without RSS sources the question stays fully
free-text.

The question with the greatest information gain for the profile is selected
first; its purpose line is written afterward and never influences the choice.

After a long-term summary, and before the must-read scope question, the
application asks a fixed follow-up question: whether the user has further
research directions to add. The application, not the LLM, displays it, and it
does not consume an LLM question. An empty answer continues to the scope
question. A non-empty answer is stored as additional direction evidence, and
the funnel resumes: every active direction is explored to the same depth
before the next summary, after which the fixed follow-up question is asked
again. When the 15-question hard ceiling is reached, the follow-up question is
skipped and the flow continues to the scope question.

The soft and hard question limits remain unchanged, but summarizing is gated
by a profile-readiness check that takes priority over the count ladder. Before
returning a summary, the LLM must verify that the profile:

- names the user's target research area from their keywords,
- names at least 2–3 concrete topics, systems, phenomena, or problem areas,
  and
- contains at least two topics that could appear in a paper title or abstract.

While any part is missing, the interview keeps asking concrete questions
within the hard ceiling of 15 answered questions; once the profile is ready,
it summarizes instead of drilling deeper. The count ladder only weights how
strongly summarizing is preferred once the readiness check passes.

When the LLM summarizes this phase, or the user chooses Finish and forces a
summary, the application stores the long-term summary and advances to the
scope question. It must not proceed directly to profile generation.

### Phase 2: deterministic scope question

The application explains that general recommendations are already governed by
the long-term profile, that `recommended` means worth a look while `must_read`
means read now, and that narrowing the must-read scope keeps those papers on
work directly related to the user's research. It does not display score bands,
thresholds, or cap rules. The application, not the LLM, displays the two stable
choices:

1. Papers that strongly match my overall research direction.
2. Only papers that directly match a narrower question, object, method, or
   goal.

A numbered answer maps directly to `research_direction` or `focused`.

A free-text answer is sent to the configured LLM for classification using this
exact response contract:

```json
{
  "scope": "research_direction | focused | unclear",
  "interpretation": "Short explanation in the selected interview language"
}
```

If the response is `unclear`, invalid, or cannot be obtained after the existing
single retry, the application shows the two choices again. A free-text answer
classified as focused is retained as the first piece of focused evidence.

Choosing research-direction sets `must_read_focus` to `null`, skips all focused
questions, and advances to the final understanding review.

### Phase 3: focused interview

Each LLM turn must:

1. Explain in one short sentence how the question helps refine must-read
   recommendations.
2. State the current inference in the chosen interview language.
3. Ask exactly one question.
4. Select single- or multiple-choice mode and offer 2–4 profile-grounded
   answers appropriate to that mode.
5. Accept selected options, free text, or both.
6. Reflect corrections in the next inference.

The interview progresses adaptively through these reasoning stages rather than
using a fixed questionnaire:

1. Propose concrete focus hypotheses inferred from the long-term profile.
2. Narrow the selected hypothesis into one primary focus.
3. Propose either mutually exclusive signal bundles in single-choice mode or
   compatible individual signals in multiple-choice mode.
4. Determine whether supporting signals are useful or whether the user
   explicitly wants primary-focus-only mode.
5. Produce a testable operational definition.

The focused phase should normally take 3–6 questions. Its soft limit is 6 and
its hard ceiling is 8. These are safeguards, not targets.

When the model decides the focus is complete, when the user chooses Finish, or
when the hard ceiling is reached, the LLM must return this exact proposal shape:

```json
{
  "action": "propose_focus",
  "primary_focus": "...",
  "supporting_signals": ["..."],
  "primary_focus_only": false,
  "must_read_definition": "..."
}
```

The proposal is written in the chosen interview language for user review. It
is valid only when:

- `primary_focus` and `must_read_definition` are non-empty and testable against
  a title and abstract.
- `primary_focus_only` is a single non-missing boolean.
- When `primary_focus_only` is `false`, supporting signals contain at least one
  unique, trimmed, non-empty string.
- When it is `true`, supporting signals are empty.

A forced proposal receives the existing single retry. If it remains invalid,
the flow ends without saving or modifying the current profile.

### Final understanding and draft

Before draft generation, the CLI displays separate sections for:

- Long-term research profile.
- Must-read scope and, when focused, the complete focus proposal.

The user may confirm, revise the long-term understanding, revise the focused
proposal, return to the preceding focused question, or discard the interview.
A long-term revision invalidates and clears focused state. A focused revision
does not alter the long-term state.

After confirmation, the final generation call translates scientific profile
and focus fields into English while retaining the confirmed filtering intent.
The complete JSON draft is displayed and must pass strict validation before
the user can save it.

## Short scope/focus update flow

The Researcher Profile menu adds **Update must-read scope/focus** when a valid
profile exists.

The flow:

1. Loads and normalizes the current profile without rewriting it.
2. Shows the current scope and focus.
3. Lets the user select the interview language.
4. Asks the same deterministic scope question.
5. For research-direction, confirms the change and saves the original profile
   fields plus `must_read_scope` and a null focus.
6. For focused, uses the saved long-term profile and current focus, when one
   exists, as tentative evidence for the focused interview.
7. Displays the localized proposal, then generates and displays the final
   English focus object before explicit save.

The short flow changes only `must_read_scope` and `must_read_focus`. It never
regenerates the existing 15 long-term fields. Cancel and failed validation leave
the profile unchanged.

Manual profile editing adds dedicated scope and nested-focus editors. Selecting
research-direction clears the focus. Selecting focused requires a complete
focus object before save. The complete profile is validated immediately before
every manual write.

## Privacy and data flow

Before either AI interview, the UI explains that each request may send the
following to the configured LLM endpoint:

- Enabled RSS journal names and URLs.
- Interview questions, answers, inferences, and corrections accumulated so far.
- The saved long-term profile and current focus in the short update flow.

Paper Monitor does not persist the transcript. It saves only a draft explicitly
confirmed by the user. Provider-side storage and processing depend on the
configured endpoint. Ollama is local only when its configured deployment is
local; a Custom or Ollama endpoint may be remote.

Questions and generated options must concern literature-filtering behavior and
must not request identity, affiliation, collaborator names, project names,
funding, contractual details, exact unpublished results, confidential
measurements, or proprietary identifiers when a general scientific description
is sufficient. The draft prompt instructs the LLM to generalize voluntarily
provided identifying details when that does not change filtering intent.

## Profile data model

Newly saved and AI-generated profiles have the existing 15 fields plus:

```json
{
  "must_read_scope": "focused",
  "must_read_focus": {
    "primary_focus": "Papers that directly help determine ...",
    "supporting_signals": [
      "uses a comparable observation type",
      "evaluates the relevant method under comparable conditions"
    ],
    "primary_focus_only": false,
    "must_read_definition": "Mark a paper must_read only when ..."
  }
}
```

Allowed scope values are `research_direction` and `focused`.

For research-direction, `must_read_focus` must be `null`. For focused, the
focus object must contain exactly the four fields shown above. Scientific text
is stored in English and describes filtering criteria rather than project
identity.

### Backward compatibility and normalization

An existing profile missing both new top-level fields is treated in memory as:

```json
{
  "must_read_scope": "research_direction",
  "must_read_focus": null
}
```

Loading and normalization never rewrite the profile file. Explicitly saving
from the full interview, short update flow, or manual editor writes the complete
17-field form.

These cases are invalid and must fail before RSS fetching or scoring:

- Only one of the two new top-level fields is present.
- The scope value is unknown.
- Research-direction has a non-null focus.
- Focused scope has a missing, null, incomplete, or inconsistent focus.
- A profile contains missing or unexpected fields after legacy normalization.

The same normalization and validation path is used by initial setup, menu runs,
scheduled `--run`, prompt construction, and all profile editors.

## Paper-evaluation response model

Focused evaluation asks the LLM to return the existing fields plus:

```json
{
  "must_read_focus_match": true,
  "must_read_focus_reason": "Directly evaluates the primary question using comparable observations."
}
```

`must_read_focus_match` must be a single non-missing boolean. The reason briefly
explains either the direct connection, the most important missing connection,
or why the title/abstract provides insufficient evidence.

Research-direction evaluation keeps the existing LLM response contract. The
application supplies an internal missing match value and empty focus reason so
the stored result rows have one stable schema without changing the broad-mode
prompt.

## Scoring and category enforcement

The application accepts a paper result only when the common fields satisfy the
response contract: score is a single finite number from 0 through 100,
`matched_topics` is a string array, and `reason` and `tldr` are non-empty
strings. The LLM-provided category is never authoritative.

After parsing:

1. In focused mode, invalid or omitted focus-match fields are conservatively
   normalized to “match not confirmed,” a warning is printed, the focus reason
   states that the model did not provide a valid focus assessment, and the
   score is capped at 89.
2. A valid `false` match is capped at 89.
3. A valid `true` match retains its score but receives no automatic increase.
4. In research-direction mode, any unexpected focus fields are ignored.
5. Category is derived from the final numeric score using these thresholds:
   - `score >= 90`: `must_read`
   - `score >= 75 && score < 90`: `recommended`
   - `score >= 60 && score < 75`: `potentially_relevant`
   - `score >= 40 && score < 60`: `peripheral`
   - `score < 40`: `low_relevance`

This threshold definition intentionally supports decimal scores without gaps.

Malformed common fields constitute a failed paper evaluation. Sequential
processing uses its existing single retry and then skips the paper. Batch
processing cannot retry one result in the submitted batch; it warns and skips
that paper. Skipped papers are not added to history and may be evaluated on a
future run.

Focused mode uses the same long-term-profile relevance rules as
research-direction mode. It appends the confirmed focus independently of
model-size profile sections and asks for a separate direct-match judgment. The
focus does not replace or reweight the long-term relevance criteria. Numeric
score bands and enforcement details remain internal and are never explained in
the interview UI.

When the abstract is absent or too weak to establish a direct match, the model
must not infer specificity from the title alone. It returns a false match and
states that evidence is insufficient. The paper can still receive a score from
its long-term relevance.

## Recommendation history

Successful evaluations add these columns to `data/recommendations.csv`:

- `must_read_scope`
- `must_read_primary_focus`
- `must_read_focus_match`
- `must_read_focus_reason`

Research-direction rows store `research_direction`, an empty primary focus,
`NA` for match, and an empty focus reason. Focused rows store the primary-focus
text active at evaluation time, so later focus changes do not make old match
values uninterpretable.

Old rows remain readable and receive missing values through row binding. Before
the first write that expands an existing history file lacking these columns,
the application creates a one-time sibling backup named
`recommendations.pre-must-read-scope.csv`. A successful later run writes the
expanded schema; there is no separate migration command.

Changing the current focus affects future evaluations only. Existing rows are
not rescored, and deduplication behavior is unchanged. Recommendation-history
detail views display the scope, saved primary focus, match value, and focus
reason when those columns are available.

## Report behavior

The existing recommendation threshold still determines which scored papers
appear in the Markdown report. `config/template.md` and its placeholder
contract remain unchanged.

For every included focused-mode paper, the output layer composes the existing
`{reason}` value as a compact explanation equivalent to:

```text
Focus: Direct match / Not a direct match / Match not confirmed — ... Overall relevance: ...
```

The stored `reason` remains the overall relevance explanation, and the stored
`must_read_focus_reason` remains separate. They are combined only during report
rendering. This guarantees compatibility with existing and custom templates
that already use `{reason}`.

Research-direction report rendering remains unchanged. No report wording may
imply that every `recommended` paper should be downloaded or read immediately.

## Failure and recovery rules

- Discard or cancellation never changes the saved profile.
- Failed profile/focus generation is retried once, then ends without saving.
- Invalid saved profiles fail before RSS fetching with an actionable message
  directing the user to Researcher Profile settings.
- Invalid focused match fields fail closed for `must_read` but retain an
  otherwise valid paper result.
- Invalid common scoring fields follow the backend-specific retry/skip behavior.
- A focus change does not mutate or reinterpret old history rows.
- The history backup makes the first schema-expanding write recoverable.
- Tests use temporary profiles, history files, and output folders; they never
  modify actual user configuration or call a real LLM provider.

## Implementation map

Implementation is staged across:

- `R/profile_interview_layer.R`, `R/initial_setup_layer.R`, and
  `Paper_Monitor.R`: normalization, validation, phase state, full/short flows,
  privacy notice, manual editing, and history detail UI.
- `R/prompt_layer.R`, `R/scoring_layer.R`, and `R/pipeline_layer.R`: normalized
  profile loading, focused prompt, shared result validation, enforcement,
  provenance, and history backup.
- `R/output_layer.R`: focused reason composition without a template-schema
  change.
- Profile, scoring, pipeline, output, and regression tests.
- Root and packaged user documentation plus local, untracked `CLAUDE.md` after
  implementation.

No dependency change is required.

## Acceptance criteria

1. The full interview always asks for must-read scope after the long-term phase.
2. Research-direction skips focused questions and preserves its prompt and
   report behavior.
3. Every generated question explains its recommendation-filtering purpose and
   does not expose numeric scoring rules.
4. Option-bearing questions declare single- or multiple-choice mode in their
   answer prompt and accept one selection, multiple selections, free text, or
   selections plus a clarification; the opening keyword question accepts free
   text only.
5. Long-term and focused counts are independent; the fixed scope question does
   not consume a focused question.
6. A valid focused proposal contains one primary focus, a consistent
   `primary_focus_only` value, supporting signals as required, and a testable
   definition.
7. Finish and the hard ceiling cannot bypass proposal validation.
8. Final review separates long-term understanding from must-read scope/focus.
9. The short flow changes only the two must-read fields.
10. The interview privacy notice accurately describes all transmitted context
   and makes no unconditional locality claim about Ollama or Custom endpoints.
11. New saves contain valid 17-field profiles; old 15-field profiles run in
    research-direction mode without being silently rewritten.
12. Partial or inconsistent profile upgrades fail before RSS fetching.
13. General recommendation remains based on the long-term profile in both
    modes; must-read focus supplies a separate direct-match decision.
14. A false or unconfirmed match cannot exceed 89 or become `must_read`.
15. A true match alone cannot turn a low-priority paper into `must_read`.
16. Long-term highly relevant non-matches may still receive `recommended`.
17. Score and category always agree for integer and decimal scores.
18. Sequential and Batch paths apply the same semantic validation and store the
    same successful-result schema.
19. Old history remains readable, its first schema expansion is backed up, and
    new rows record scope plus primary-focus provenance.
20. Every included focused paper explains focus relationship and overall
    relevance through the existing Reason placeholder.
21. Research-direction output and custom templates remain compatible.
22. All existing and new tests pass without real provider calls or writes to
    user data.
23. Phase-1 questions form a funnel that starts from the user's own keywords
    and descends one granularity level at a time — keywords, then
    sub-directions or aspects, then topics and problem classes — and never
    jumps to highly specific topics. The profile's finest level is that third
    level, it descends along the research subject rather than the methodology,
    and it does not descend into methods, algorithms, model families, tools,
    theoretical guarantees, or datasets. A level is clear only when its
    answers name at least one concrete item and add no new unresolved branch;
    while it is unclear, the interview asks further same-level questions,
    keeps each question, inference, and option set at one level with peer
    options, treats every keyword or selection as active, and follows meta or
    non-specific answers with a concrete-content question at the current
    level.
24. The opening question asks for the user's target research area as one or
    more free-text keywords with an empty options list; when enabled RSS
    sources exist, it instead offers 2–4 candidate keywords derived from that
    scope as options.
25. Phase-1 summarizing is gated by the operationalized profile-readiness
    check, which takes priority over the count ladder; the 15-question hard
    ceiling is unchanged.
26. The question-purpose line is written after the question is chosen, never
    changes which question is selected, and stays within one sentence of at
    most 25 words.
27. After a long-term summary the application asks a fixed question about
    additional research directions before the must-read scope question: an
    empty answer advances to the scope question, a non-empty answer is stored
    as direction evidence and resumes the funnel, and the 15-question hard
    ceiling skips the question.

## Deferred enhancements

- Multiple named or concurrent focuses.
- Time-limited focuses and automatic expiration.
- Feedback learning from downloads, reading decisions, or report interactions.
- Separate long-term and immediate-relevance numeric scores.
- Historical re-scoring after a focus change.
- Automatic PDF download or full-text analysis.
