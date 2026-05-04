#!/usr/bin/env python3
from pathlib import Path
import json
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

BASE = Path('/home/hermes/.hermes/profiles')
PERMISSIONS = '274877936704'

for profile_dir in sorted(BASE.iterdir() if BASE.exists() else []):
    if not profile_dir.is_dir():
        continue
    env_path = profile_dir / '.env'
    if not env_path.exists():
        continue
    env = {}
    for line in env_path.read_text().splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            env[k] = v
    token = env.get('DISCORD_BOT_TOKEN', '')
    print(f'[{profile_dir.name}]')
    if not token or token.startswith('REPLACE_WITH_'):
        print('  status: missing token')
        print()
        continue
    try:
        req = Request('https://discord.com/api/v10/oauth2/applications/@me', headers={'Authorization': f'Bot {token}', 'User-Agent': 'Hermes-Agent'})
        with urlopen(req, timeout=20) as r:
            app = json.loads(r.read().decode())
        client_id = app['id']
        print('  client_id:', client_id)
        print('  invite_url:', f'https://discord.com/oauth2/authorize?client_id={client_id}&scope=bot%20applications.commands&permissions={PERMISSIONS}')
    except (HTTPError, URLError, KeyError, json.JSONDecodeError) as exc:
        print('  status: token present but lookup failed')
        print('  error:', exc)
    print()
