# Phase C Hermes Team Rollout

Profiles created
- pm
- researcher
- designer
- designbuilder
- softwarebuilder
- reviewer
- qa

Wrapper commands created
- pm
- researcher
- designer
- designbuilder
- softwarebuilder
- reviewer
- qa

Profile paths
- /home/hermes/.hermes/profiles/pm
- /home/hermes/.hermes/profiles/researcher
- /home/hermes/.hermes/profiles/designer
- /home/hermes/.hermes/profiles/designbuilder
- /home/hermes/.hermes/profiles/softwarebuilder
- /home/hermes/.hermes/profiles/reviewer
- /home/hermes/.hermes/profiles/qa

Role intent
- pm: PRD, slicing, prioritization, acceptance criteria
- researcher: AI trend scanning and team-facing research summaries
- designer: UX, IA, interaction design, product copy
- designbuilder: UI implementation and polish
- softwarebuilder: feature implementation and integration
- reviewer: spec/code review and regression risk detection
- qa: scenario testing and bug reporting

Researcher mission
- Run a daily vibe-coding trend scan via web research
- Distill only meaningful updates
- If there is no meaningful update, do not send anything
- If there is a meaningful update, send a concise structured memo to affected teammates
- Receiving teammates must record the update and translate it into role-specific implications

Research allowlist added to firewall source
- File updated: /workspace/.devcontainer/init-firewall.sh
- Added AI research group with domains such as:
  - arxiv.org
  - openreview.net
  - paperswithcode.com
  - huggingface.co
  - lmarena.ai
  - artificialanalysis.ai
  - x.com
  - reddit.com
  - news.ycombinator.com
  - lesswrong.com
  - alignmentforum.org
  - semianalysis.com
  - theinformation.com
  - techcrunch.com
  - ai.google.dev
  - deepmind.google
  - mistral.ai
  - meta.com
  - ai.meta.com
  - cohere.com
  - together.ai
  - replicate.com
  - modal.com
  - metaculus.com
  - manifold.markets
  - zhihu.com
  - weibo.com
  - linkedin.com

To apply firewall change
- Rebuild/restart the dev container image that uses init-firewall.sh
- The running container will not automatically pick up firewall source edits

Recommended Discord structure
- One Discord app/bot per teammate for the cleanest UX
- Recommended bot names:
  - Hermes PM
  - Hermes Researcher
  - Hermes Designer
  - Hermes Design Builder
  - Hermes Software Builder
  - Hermes Reviewer
  - Hermes QA

Recommended channel layout
- #pm-room
- #research-room
- #design-room
- #design-builder-room
- #software-builder-room
- #review-room
- #qa-room

Recommended invite scopes
- bot
- applications.commands

Recommended bot permissions
- View Channels
- Send Messages
- Read Message History
- Embed Links
- Add Reactions
- Create Public Threads
- Send Messages in Threads

Recommended bot settings
- Enable Message Content Intent
- If needed, also enable Server Members Intent

Per-profile Discord rollout steps
1. Create a Discord app + bot in the Developer Portal
2. Copy bot token into that profile's .env as DISCORD_BOT_TOKEN
3. Optionally set DISCORD_ALLOWED_USERS and DISCORD_HOME_CHANNEL in that profile's .env
4. Start the gateway for that profile, e.g.:
   - pm gateway run
   - researcher gateway run
   - designer gateway run
   - designbuilder gateway run
   - softwarebuilder gateway run
   - reviewer gateway run
   - qa gateway run
5. Invite the bot to the server using that app's OAuth2 URL
6. Test mention and thread behavior in the assigned channel

Important operational note
- If you use one Discord bot token across multiple profiles, you can get collisions or confusing behavior.
- Prefer one bot token per teammate profile.

Suggested researcher output format
- Signal:
- Source:
- Confidence:
- Why it matters:
- Affected teammates:
- Recommended action:

Suggested handoff patterns
- researcher -> pm/designer/designbuilder/softwarebuilder/reviewer/qa
- pm -> designer/designbuilder/softwarebuilder/reviewer/qa
- designer -> designbuilder/softwarebuilder
- softwarebuilder -> reviewer/qa
- reviewer -> softwarebuilder/pm
- qa -> pm/softwarebuilder/designbuilder

Supporting files
- /workspace/researcher-daily-vibe-coding-prompt.txt
- /workspace/researcher-sharing-contract.md
