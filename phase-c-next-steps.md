# Phase C Next Steps

Current status
- Researcher profile exists and has a Discord token configured.
- Researcher gateway process is running.
- Daily researcher vibe-coding scan cron job is scheduled.
- Other teammate profiles exist but still need their own Discord bot tokens.

Immediate next actions
1. Verify researcher bot responds in Discord.
2. Promote researcher output to a stable distribution channel/thread.
3. Create PM bot and Reviewer bot next.
4. Add a simple bootstrap helper for future teammate bot rollout.

Recommended rollout order
1. researcher
2. pm
3. reviewer
4. softwarebuilder
5. designer
6. designbuilder
7. qa

Operational note
- Each profile should have its own Discord bot token.
- Avoid sharing one bot token across multiple profiles.
- Use `hermes --profile <name> gateway run` per teammate.
