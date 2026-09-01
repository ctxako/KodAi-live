<div align="center">

# KodAi

**A private assistant for iPhone that runs a 1.2B language model entirely on the device.**

*No cloud. No API keys. No network calls.*

![Platform](https://img.shields.io/badge/platform-iOS%2026%20%7C%20macOS%2026-0b1220?style=for-the-badge&labelColor=05070e)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?style=for-the-badge&labelColor=05070e)
![Inference](https://img.shields.io/badge/inference-llama.cpp%20b9775-4FD8E8?style=for-the-badge&labelColor=05070e)
![Model](https://img.shields.io/badge/LFM2.5-1.2B%20Q4__K__M-b388ff?style=for-the-badge&labelColor=05070e)

<br>

<img src="docs/demo.gif" width="300" alt="Typing a request into KodAi; the model picks a tool, fills in an editable event card, and the event appears in Apple Calendar.">

<sub>Every step above runs on the phone. No server, no API key, no network.</sub>

</div>

---

## The problem

KodAi is an iPhone assistant with no server behind it. A 1.2B-parameter model ships inside the app bundle and runs through llama.cpp on the device's GPU. You talk to it normally; when you ask for something actionable it calls a tool, such as creating a Calendar event, adding a Reminder, or searching your local notes.

A 1.2B model is roughly a hundredth the size of the models that made tool-calling look easy. Left alone it emits malformed JSON, invents arguments, narrates instead of acting, and routes "show me my to-do list" into creating a to-do. Most of the work here is closing that gap. The output format is constrained at the sampler by a grammar built from the tool catalog, so an invalid call cannot be generated in the first place. Whatever gets through is checked by a validator that owns the semantics the grammar cannot express.

The next problem is not asking the model at all. Every message goes down the first of four routes that matches: a backend fact ("what time is it"), a pinned-tool intent ("remind me to…"), a slash command, or a full model turn. When the tool is already known, the model's job shrinks from picking one of six tools and filling its arguments to filling one schema, which a small model does more accurately.

Then there is the phone itself. Decoding runs off the main thread with a watchdog, paces when the device gets hot, and buffers output so multi-byte characters do not arrive as garbage mid-stream. Context is sized by device tier and budgeted per source, so no one part of the prompt crowds out the rest, and the app shows how full the window was on the last turn.

The last problem is being wrong safely. Every write the model originates is a proposal rather than an action: an editable card you confirm. One tool call per turn, no invented ids, questions never create, and time is resolved by code rather than trusted from the model. A failure gets one silent retry seeded with what went wrong, then a specific message about the field that was wrong.

---

## How it's built

`KodaiCore` is a standalone Swift package with three targets and no third-party dependencies:

```mermaid
flowchart LR
    CORE(("KodaiCore"))
    K["KodaiKernel<br/><i>tool grammar · parsing<br/>validation · routing config<br/>context assembly</i>"]
    R["KodaiRuntime<br/><i>llama.cpp wrapper<br/>tokenize · prefill<br/>decode · sample</i>"]
    P["KodaiPersistence<br/><i>SwiftData models<br/>schema migrations<br/>context providers</i>"]

    CORE --- K
    CORE --- R
    CORE --- P

    style CORE fill:#05070e,stroke:#4FD8E8,stroke-width:3px,color:#4FD8E8
    style K fill:#12304a,stroke:#4FD8E8,stroke-width:2px,color:#EAF2F5
    style R fill:#3a2a44,stroke:#F2C45A,stroke-width:2px,color:#EAF2F5
    style P fill:#1a2f52,stroke:#b388ff,stroke-width:2px,color:#EAF2F5
```

That package is what unifies the two apps. They differ underneath: iOS runs llama.cpp with a bundled GGUF, macOS runs Apple Foundation Models with an optional Ollama backend. The runtime sits behind a protocol, and everything above it is shared, including the routing config, the parser and validator, context assembly, and persistence.

It also makes the evaluation harness meaningful. Labelled inputs run through the same shipped routing config the iPhone app uses, so there is no second copy to drift out of sync, and a regression in the app is a regression in the eval. It also lets 157 tests run without loading a 700 MB model.

Inside the iPhone app:

```mermaid
flowchart TD
    UI["🪟 Chat surface<br/><i>SwiftUI · one NavigationStack</i>"]
    ROUTE["🚦 ChatInputRouter<br/><i>facts · intent · commands · model</i>"]
    TURN["🔁 AssistantTurnCoordinator<br/><i>proposals, guards, retry</i>"]
    KERNEL["🧭 KodaiKernel<br/><i>grammar · parse · validate</i>"]
    RUNTIME["⚙️ KodaiRuntime<br/><i>llama.cpp · LFM2.5 1.2B</i>"]
    EK["📅 EventKit<br/><i>Calendar · Reminders</i>"]
    PERSIST["💾 SwiftData<br/><i>schema V8 · migrations</i>"]

    UI --> ROUTE --> TURN
    TURN --> KERNEL --> RUNTIME
    TURN --> EK
    TURN --> PERSIST

    style UI fill:#12304a,stroke:#4FD8E8,stroke-width:2px,color:#EAF2F5
    style ROUTE fill:#14304f,stroke:#47d1ef,stroke-width:2px,color:#EAF2F5
    style TURN fill:#1a2f52,stroke:#b388ff,stroke-width:2px,color:#EAF2F5
    style KERNEL fill:#202d54,stroke:#b388ff,stroke-width:2px,color:#EAF2F5
    style RUNTIME fill:#3a2a44,stroke:#F2C45A,stroke-width:2px,color:#EAF2F5
    style EK fill:#2a2a50,stroke:#ff6fae,stroke-width:2px,color:#EAF2F5
    style PERSIST fill:#2b2f38,stroke:#7C93A6,stroke-width:2px,color:#EAF2F5
```

**Tool catalog (six).** `calendar_create_event`, `calendar_list_events`, `reminders_create`, `reminders_list`, `kotes_search`, `respond`. Read-only tools run automatically; the two creates go through the proposal sheet.

**Kotes** are the local knowledge base, plain notes with no relationships. The model can read them via `kotes_search` but has no write path.

**Privacy controls.** *Manage Task Information* deletes selected creation receipts and their tool records, optionally deleting the Apple item as well, and reports only what actually persisted. *Delete All Local Data* purges every KodAi store without touching Calendar, Reminders, permissions, or the bundled model.

---

## The macOS companion

A SwiftUI workspace on Apple Foundation Models, sharing `KodaiCore`. Persistent sessions, project organization, a daily briefing engine, and a context inspector that shows exactly what the model sees before each generation. Optional Ollama backend for larger local models.

It exists to show the core is actually shared: the same context assembly and persistence, with a different model runtime and interface.

---

## Stack

Swift 6.2 · SwiftUI · SwiftData · Swift Testing · llama.cpp b9775 (vendored XCFramework) · GBNF grammar-constrained sampling · EventKit · Apple Foundation Models (macOS) · **no third-party Swift packages, no network calls**

---

## Design principles

**Local-first by default.** On-device inference and local storage. No API keys, no external services.

**The assistant exposes its work.** Context used, tools called, arguments extracted, and reroutes applied are visible in a per-answer timeline, with raw token decisions one level below it.

**Native, calm, and fast.** It should belong beside Notes, Reminders, and Calendar. Semantic text styles, Reduce Motion-aware transitions, system contrast and transparency behavior throughout.

---

<div align="center">

**Source is private.** This repository documents how it is built.

<sub>Built by <a href="https://github.com/ctxako">@ctxako</a></sub>

</div>
