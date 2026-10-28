---
name: debate
description: >
  Run a structured, multi-round debate between two or more AI models on a single question, then
  moderate and summarise the result. Use this whenever the user says "debate", asks to have
  models argue, discuss, or go head-to-head on a question, wants to see where different models
  disagree, or wants a contested decision stress-tested from several angles before committing.
  The skill asks for the models, the question, and any relevant context before starting, runs
  one agent per model so each keeps its own memory across rounds, and returns a moderator's
  summary of agreements, disagreements, strongest arguments, and a verdict.
---

# Debate

## What this skill does

A debate is a way to get a sharper answer to a contested question than any single model gives on
its own. Each participating model argues its position, reads what the others said, and responds.
Disagreements get surfaced instead of smoothed over, weak arguments get challenged, and the
moderator (you) ends with a synthesis that says where the models converged, where they still
differ, and why.

You are the **moderator**, not a participant. You do not argue a side. You set the question up,
relay statements between participants, keep the rounds on topic, and write the final summary.

## 1. Gather the inputs

Before starting, you need three things. Ask for whatever is missing in a single message rather
than drip-feeding questions. If the harness has a structured question tool, use it; otherwise
ask in plain text.

1. **The participants.** Which models should debate. Need at least two. If the user says
   "you pick" or doesn't care, use the latest flagship from each of three different providers
   (for example Claude Opus, GPT, and Gemini Pro) at high reasoning effort. Two instances of the
   same model are allowed if the user explicitly asks for it.
2. **The question.** A single question or proposition. If the user gives a vague topic, help
   them turn it into one debatable sentence before proceeding, for example "Should we migrate
   the billing service to event sourcing?" rather than "event sourcing".
3. **Relevant context.** Anything the participants need to argue well: a design doc, a diff,
   constraints, prior decisions, the audience, what the user already believes. Read files the
   user points at. If the user says there is none, proceed.

Also confirm two defaults in the same message, so the user can override them without being
asked again:

- **Format.** Default is *honest positions*: each model argues what it actually thinks. The
  alternative is *assigned sides*: you split the participants across positions (for / against,
  or option A / B / C) and each argues the side it was given regardless of its own view.
  Assigned sides are better for stress-testing a decision; honest positions are better for
  finding out what the models actually believe.
- **Stopping rule.** Default is *run to convergence*: the debate keeps going, rebuttal after
  rebuttal, until the participants have stopped producing new arguments (see "When to stop"
  below). There is no cap on the number of rounds. If the user wants a fixed number of rounds
  instead, use that.

If the question is missing, do not start. If models are missing, propose the default three and
start once the user confirms or after a short wait if they said to proceed.

## 2. Resolve the models

Use the harness's subagent tools to start **one agent per participating model**, so that each
participant keeps its own memory across rounds. Continue the same agent for every round instead
of starting a fresh one, so it remembers what it already said and what it was challenged on.

If a named model is unavailable in this harness, or you cannot reach the provider, **report that
and stop to ask** rather than silently substituting a different model. The point of the debate
is the specific models the user chose. If you can only reach one model, say so; a debate with one
participant is not a debate.

Give every participant the same briefing. See `references/participant-briefing.md` for the
template. The briefing includes the question, the full context, its assigned side if any, the
round structure, the length limit per statement, and the rule that it must engage with the
other participants' actual arguments rather than restating its own.

## 3. Run the rounds

Run each round's statements **in parallel** across participants, then collect them before
starting the next round. Participants never talk to each other directly; everything goes through
you.

**Opening statements.** Each participant states its position and its two or three strongest
supporting arguments. Send the briefing and ask for the opening. Nobody sees anyone else's opening
until all are in.

**Rebuttal rounds.** Repeat for as many rounds as the debate needs. For each round, send every
participant the other participants' most recent statements, labelled by model name, and ask it
to:

- respond to the strongest point made against its position,
- concede anything it now agrees with, explicitly,
- say what it still disagrees with and why,
- avoid repeating anything it already said,
- end with one line: `CONTINUE` if it has a new argument or an unanswered challenge left to
  make, or `NOTHING FURTHER` if it does not.

Hold the length to roughly 250 to 400 words per statement so the debate stays readable. Say the
limit in the briefing and remind participants if they run long.

**When to stop.** After each rebuttal round, decide whether to run another. Keep going while any
participant said `CONTINUE` and its statement actually contained something new. Move to closings
when any of these is true:

- every participant said `NOTHING FURTHER`,
- the last round added no new arguments, concessions, or evidence, only restatements, even if a
  participant still said `CONTINUE`,
- the participants have converged and are only agreeing with each other,
- the user asked for a fixed number of rounds and it has been reached, or the user tells you to
  stop.

Do not stop just because the debate is long. A debate that is still producing new points on
round eight is doing its job. Do stop when it is going in circles, and say in the summary which
rule ended it.

**Closing statements.** Each participant gets the final round's statements and gives a short
closing: its final position, what changed its mind if anything did, and what it thinks the
crux of the remaining disagreement is. Ask for a confidence level out of 10 in its final
position.

Between rounds, watch for drift. If a participant wanders onto a different question, or two
participants are arguing past each other because they are using a term differently, intervene:
add a one-line moderator note to the next round's prompt that names the drift and pulls them back.
Do not add your own arguments.

## 4. Moderate and summarise

Once the closings are in, write the summary. Use the structure in
`references/report-template.md`. It covers:

- the question as debated, the format, how many rounds it ran, and which rule ended it,
- each participant's final position and confidence in one line,
- **points of agreement**, including anything a participant conceded during the debate,
- **points of disagreement**, with the strongest argument on each side in the participants'
  own terms,
- **arguments that didn't survive**: claims that were made and then successfully rebutted,
- the **crux**: the one or two things the disagreement actually turns on,
- your **moderator's assessment**: which side made the stronger case and why, flagging where
  your own view is doing the work rather than the participants' arguments,
- **recommended next steps** for the user, if the question was a decision.

Be faithful to what the participants said. Do not invent agreements or sharpen disagreements for
effect. If a participant gave no confidence score, write `no score`. If a model was unavailable,
say so at the top of the report.

Keep the full transcript. Put it after the summary in a collapsed section, or in a file next to
the user's work if the harness can write one, so the user can check any claim in the summary
against the source.

## Guardrails

- The moderator does not argue a side, in the prompts or in the summary, except in the clearly
  labelled assessment at the end.
- Never substitute a model the user didn't ask for without telling them.
- Every participant gets identical context. Do not give one side extra information.
- Keep the debate on the one question. A new question is a new debate.
- Participants' work is read-only. They read context and write arguments. They do not edit
  files, run commands that change state, or make external calls on the user's behalf.
