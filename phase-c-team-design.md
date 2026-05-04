# Phase C Team Design

Team roles
- PM
- Researcher
- Designer
- Design Builder
- Software Builder
- Reviewer
- QA

Role responsibilities
- PM: roadmap, PRD, slicing, acceptance criteria, task routing
- Researcher: daily AI/vibe-coding research, trend distillation, team-facing implications
- Designer: user flow, information architecture, UX rationale, copy, interaction design
- Design Builder: visual implementation, component polish, layout/state/empty-state quality
- Software Builder: feature implementation, APIs, state, integration, refactor
- Reviewer: spec compliance, code quality, regression/risk review
- QA: scenario validation, bug reports, edge-case and workflow testing

Research sharing flow
1. Researcher performs a daily trend scan.
2. If there is no meaningful update, researcher sends nothing.
3. If there is a meaningful update, researcher produces a concise memo:
   - Signal
   - Source
   - Confidence
   - Why it matters
   - Affected teammates
   - Recommended action
4. Receiving teammates record the update in their role context and convert it into implications.

Team handoff model
- researcher -> pm, designer, designbuilder, softwarebuilder, reviewer, qa
- pm -> designer, designbuilder, softwarebuilder, reviewer, qa
- designer -> designbuilder, softwarebuilder
- softwarebuilder -> reviewer, qa
- reviewer -> softwarebuilder, pm
- qa -> pm, softwarebuilder, designbuilder

Recommended Discord operating model
- One bot per teammate
- One primary channel per teammate role
- Optional shared research digest channel for cross-team updates

Automation status
- Profiles created
- Role SOULs installed
- Researcher daily scan cron created
- Researcher bot token configured and gateway running
- Helper scripts created for invite URL generation and gateway startup
