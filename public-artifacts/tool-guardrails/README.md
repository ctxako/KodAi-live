# tool-guardrails

A small, tested Swift reference implementation of the boundary between a
language model's output and a write to someone's calendar.

**This is an independently authored artifact written from a specification, not
KodAi application source and not a sanitized extract of it.** It exists so the
approach described in the [root README](../../README.md) can be read and run
rather than taken on faith. No third-party packages, no network, no LLM runtime,
no EventKit — Swift 6 and Foundation only.

## Two gates

A tool call has to clear two independent checks, and they ask different
questions. Neither can do the other's job.

**Gate 1 — shape.** `GBNFCompiler.compile(_:)` turns a tool catalog into a
deterministic [GBNF](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)
grammar for llama.cpp's sampler. It runs *during* generation, so malformed
output is never produced in the first place: one call per turn, only catalogued
tool names, only catalogued argument keys, required keys present.

**Gate 2 — meaning.** `ToolCallValidator` runs *after* generation and asks what
a grammar cannot: is `"start_date"` actually a date, or the word "tomorrow"?
Has it already happened? Does the end fall after the start? Is the title blank?
`now` is injected, so "in the past" is deterministic under test.

Between them sits `ToolCallParser`, which is plumbing rather than a gate — it
turns generated text into a neutral `RawToolCall` so gate 2 has something to
inspect. Malformed JSON, an empty array, and more than one call all fail
cleanly; JSON booleans normalize to `"true"` / `"false"`.

## Why one gate is not enough

Constraining the sampler removes a whole class of failure — a small model cannot
emit unbalanced braces, invent a tool, or misspell an argument key if those
tokens were never available to it. But a grammar reasons about shape, not
meaning. `"start_date": "tomorrow at noon"` is a perfectly valid string. So is a
date that has already passed. Every check that depends on a value, on a
relationship between two fields, or on the current time has to happen after
parsing, which is the entire reason gate 2 exists.

## Proposals, not actions

`ValidationResult` has two cases: `.proposal` and `.rejection`. There is no
execution case. A validated call is something to *show* a person — an editable
card they confirm — and an integrating UI must require that confirmation before
any write. The validator touches no store.

## Example

Input:

```
Create lunch with Sam tomorrow at noon
```

Illustrative model output:

```json
[{"name":"calendar_create_event","arguments":{"title":"Lunch with Sam","start_date":"2026-09-01T12:00:00-04:00"}}]
```

Result:

```
proposal(ValidatedToolCall(name: "calendar_create_event",
                           action: .createEvent(title: "Lunch with Sam", …)))
```

Nothing is written. The proposal goes to the user.

## Running the tests

```bash
cd public-artifacts/tool-guardrails
swift test
```

The suite covers grammar determinism and required-field handling, parser
failure modes and boolean normalization, and the validator's rejections —
missing title, unparseable date, end before start, past event — against a fixed
clock, plus the two proposal paths.

`Fixtures/calendar-reminders-tools.json` is the catalog the tests compile: the
three example tools, `calendar_create_event`, `reminders_create`, and `respond`.
