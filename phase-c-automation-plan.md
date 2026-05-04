# Phase C Automation Plan

What can be automated
- Hermes profile creation and role-specific SOUL setup
- Per-profile env templating
- Per-profile gateway start/stop commands
- Daily researcher trend scan scheduling
- Research summary routing rules and teammate recording contract

What still needs manual setup
- Creating Discord applications/bots in the Discord Developer Portal
- Copying each bot token into the matching profile `.env`
- Inviting each bot to the Discord server via OAuth URL
- First live smoke test in Discord per teammate bot

Recommended automation layers

1. Bootstrap automation
- Script creates/updates teammate profiles
- Script writes SOUL.md defaults
- Script writes `.env` placeholders
- Script prints invite URLs once bot tokens are present

2. Runtime automation
- One gateway process per profile
- Run with tmux or user services
- Suggested commands:
  - `hermes --profile pm gateway run`
  - `hermes --profile researcher gateway run`
  - `hermes --profile designer gateway run`
  - `hermes --profile designbuilder gateway run`
  - `hermes --profile softwarebuilder gateway run`
  - `hermes --profile reviewer gateway run`
  - `hermes --profile qa gateway run`

3. Research automation
- Daily cron for researcher trend scan
- Output only when there is a material update
- Structured memo fields:
  - Signal
  - Source
  - Confidence
  - Why it matters
  - Affected teammates
  - Recommended action

4. Teammate recording automation
- Each receiving teammate should append incoming research decisions to their notes or session log
- In practice, this can be done through:
  - role-specific channels/threads
  - a shared research digest channel
  - or a lightweight notes file / docs path

Recommended Discord operating model
- One bot per teammate profile
- One channel per teammate role
- Optional shared `#research-digest` channel for researcher outputs

Recommended next automation step
- After the researcher bot is confirmed live, create one recurring daily researcher cron job.
- After PM/reviewer/qa bots are live, wire a simple team routing convention:
  - researcher posts summary
  - PM translates into roadmap/PRD implication
  - others record role-specific implication
