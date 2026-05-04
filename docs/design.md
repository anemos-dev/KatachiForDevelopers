# Katachi for Developers Design

## Overview

Katachi is a product family for turning rough ideas into structured, actionable cards.
The first release, **Katachi for Developers**, is an iPhone app for developers to capture ideas quickly, keep technical context attached, and turn rough thoughts into implementation-ready notes later.

## Product Goal

Katachi for Developers should help users avoid losing small but valuable ideas during development.
It is not a general-purpose note app. It is optimized for developer thought flow.

Core strengths:

- fast capture
- easy rediscovery
- lightweight organization
- support for technical context

## Target Users

- indie developers
- app engineers
- makers who often get feature ideas while building
- people who mix product ideas, implementation notes, and technical hypotheses

## Brand Architecture

- Parent brand: Katachi
- First app: Katachi for Developers
- Future app candidate: Katachi for Designers

The shared promise is "turn a vague thought into a form you can act on." Each audience-specific app should keep the same capture-and-card model while changing templates, vocabulary, and workflows for that audience.

## Core Problem

- ideas disappear because opening a general memo app feels too heavy
- short notes lose meaning later if technical context is missing
- bug hypotheses, feature ideas, and article ideas get mixed together
- saving is easy, but reviewing and growing ideas is not

## Core Concept

**1 idea = 1 card = 1 reusable seed**

Instead of long note pages, the app treats each idea as a compact unit that can later be filtered, revisited, and expanded.

## MVP Scope

The first version should focus on capture, organization, and rediscovery.

Included:

- quick idea creation
- idea list
- detail editing
- tags
- search
- favorite flag
- sorting
- basic status management

Not included:

- cloud collaboration
- AI features
- web sync
- rich file attachment system
- shared workspaces

## Information Architecture

Each idea should have:

- title
- body
- kind
- status
- created date
- updated date
- tags
- priority
- favorite flag
- optional next action
- optional project name

Suggested kinds:

- feature
- uiux
- tech
- bug
- article
- business
- note

Suggested statuses:

- inbox
- exploring
- planned
- shipped
- onHold
- dropped

## Main Screens

### Home

Purpose:
Browse, search, and reopen saved ideas.

Main elements:

- search bar
- filter chips
- sort control
- card list
- floating add button

Each card shows:

- title
- body preview
- tags
- kind
- status
- updated date
- favorite indicator

### Quick Capture

Purpose:
Save an idea in a few seconds without breaking concentration.

Design rules:

- title and body are enough to save
- advanced fields stay collapsed by default
- saving should be one primary action

Optional expanded fields:

- kind
- tags
- status
- priority
- next action

### Detail

Purpose:
Grow a rough note into something usable.

Available actions:

- edit content
- edit tags
- change status
- change priority
- set next action
- mark favorite
- attach project context

### Filter View

Filter axes:

- kind
- status
- tags
- favorite
- priority

## UX Principles

### Capture must be fast

The product wins or loses on how quickly a thought can be saved.
Do not require too many fields up front.

### Rediscovery matters

Saving alone is not enough.
The list should help users think, "I can work on this now."

### Developer context is a differentiator

This app should make it easy to preserve:

- related technology
- target app or project
- implementation direction
- next experiment

## Data Model Draft

### Idea

- `id: UUID`
- `title: String`
- `body: String`
- `kind: IdeaKind`
- `status: IdeaStatus`
- `priority: Int`
- `isFavorite: Bool`
- `projectName: String?`
- `nextAction: String?`
- `createdAt: Date`
- `updatedAt: Date`

### Tag

- `id: UUID`
- `name: String`
- `colorHex: String?`

## App Flow

1. Open the list
2. Tap add
3. Save with title and body
4. Return to the list or continue editing details
5. Revisit by search, tag, or status

## Priorities

Priority A:

- create
- list
- detail edit
- tags
- search

Priority B:

- status
- favorites
- sorting
- filtering

Priority C:

- project grouping
- widget
- voice input
- markdown

## Recommendation

The best starting point is:

- fast capture plus light organization
- card-based list on iPhone
- plain text body first
- SwiftData for local storage
- single-device experience before sync

## Implementation Note

The app display name should be **Katachi** so it stays short on the Home Screen.
Store-facing copy should use **Katachi for Developers** to make the target user clear.
