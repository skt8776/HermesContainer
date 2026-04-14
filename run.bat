@echo off
REM Hermes Agent Hardened Dev Container Launcher (Windows)
REM
REM Usage:
REM   run.bat build                  - Build image
REM   run.bat init ^<name^>            - Create or select project folder
REM   run.bat login                  - Codex OAuth (ChatGPT Pro)
REM   run.bat claude-login           - Claude Code OAuth (always re-prompts)
REM   run.bat claude-status          - Check Claude Code auth (no re-prompt)
REM   run.bat install-claude-skill   - Install Claude Code skill into Hermes
REM   run.bat install-codex-skill    - Install Codex skill into Hermes
REM   run.bat install-skills         - Install both delegation skills
REM   run.bat setup                  - Hermes setup wizard
REM   run.bat gateway-setup          - Configure Discord/Slack gateway
REM   run.bat up                     - Start long-running container
REM   run.bat attach                 - Open shell in running container
REM   run.bat logs                   - Show gateway and OAuth proxy logs
REM   run.bat stop                   - Stop long-running container
REM   run.bat run                    - Run hermes interactively
REM   run.bat start                  - Interactive shell
REM   run.bat noshield               - DEBUG: shell without firewall

setlocal enabledelayedexpansion

set "IMAGE_NAME=hermes-dev"
set "CONTAINER_NAME=hermes-agent"
set "WORKSPACE=%cd%"

if "%DEPLOY_HOST%"=="" set "DEPLOY_HOST=general-01.kimys.net"

REM Volume mounts: workspace bind + persistent named volumes
set "VOLUMES=-v %WORKSPACE%:/workspace -v hermes-codex-auth:/home/hermes/.codex -v hermes-claude-auth:/home/hermes/.claude -v hermes-home:/home/hermes/.hermes -v hermes-ssh:/home/hermes/.ssh -v hermes-bash-history:/commandhistory"

REM Docker runtime hardening
set "HARDENING=--cap-drop=ALL --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=CHOWN --cap-add=SETUID --cap-add=SETGID --cap-add=DAC_OVERRIDE --security-opt=no-new-privileges --pids-limit=1024 --memory=6g --memory-swap=6g --cpus=3"

REM Port forwarding: localhost only
set "PORTS=-p 127.0.0.1:10531:10531 -p 127.0.0.1:8090:8090"

set "ENVARGS=-e DEPLOY_HOST=%DEPLOY_HOST%"

REM Command dispatch
if "%~1"=="" goto :help
if /i "%~1"=="build"                goto :build
if /i "%~1"=="init"                 goto :init
if /i "%~1"=="login"                goto :login
if /i "%~1"=="claude-login"         goto :claude_login
if /i "%~1"=="claude-status"        goto :claude_status
if /i "%~1"=="install-claude-skill" goto :install_claude_skill
if /i "%~1"=="install-codex-skill"  goto :install_codex_skill
if /i "%~1"=="install-skills"       goto :install_skills
if /i "%~1"=="setup"                goto :setup
if /i "%~1"=="gateway-setup" goto :gateway_setup
if /i "%~1"=="up"            goto :up
if /i "%~1"=="attach"        goto :attach
if /i "%~1"=="logs"          goto :logs
if /i "%~1"=="stop"          goto :stop
if /i "%~1"=="run"           goto :run
if /i "%~1"=="start"         goto :start
if /i "%~1"=="noshield"      goto :noshield
goto :help

:build
docker build -f .devcontainer/Dockerfile -t %IMAGE_NAME% .
goto :eof

:init
if "%~2"=="" (
    echo Usage: %~nx0 init ^<project-name^>
    exit /b 1
)
set "PROJECT_NAME=%~2"
echo %PROJECT_NAME%| findstr /r "^[a-zA-Z0-9_-][a-zA-Z0-9_-]*$" >nul
if errorlevel 1 (
    echo Error: project name must contain only alphanumeric, hyphens, underscores
    exit /b 1
)
set "PROJECT_DIR=%WORKSPACE%\%PROJECT_NAME%"
if exist "%PROJECT_DIR%\" (
    echo Using existing project: %PROJECT_DIR%
) else (
    echo Creating new project: %PROJECT_DIR%
    mkdir "%PROJECT_DIR%"
    (
        echo # %PROJECT_NAME%
        echo.
        echo Project managed by Hermes Agent inside the hardened dev container.
        echo.
        echo ## Notes
        echo - This folder is excluded from the parent dev-container git repository.
        echo - If you want to version this project separately, run `git init` inside this folder.
    ) > "%PROJECT_DIR%\README.md"
)
findstr /x "/%PROJECT_NAME%/" "%WORKSPACE%\.gitignore" >nul 2>&1
if errorlevel 1 (
    echo /%PROJECT_NAME%/>> "%WORKSPACE%\.gitignore"
    echo Added /%PROJECT_NAME%/ to .gitignore
)
echo %PROJECT_NAME%> "%WORKSPACE%\.current-project"
echo Active project: %PROJECT_NAME%
goto :eof

:login
REM Use device-auth: Codex prints a code + URL; user pastes code on host browser.
REM Avoids port-forwarding complexity across Docker/WSL/Windows networking.
docker run --rm -it %HARDENING% %VOLUMES% %ENVARGS% %IMAGE_NAME% codex login --device-auth
goto :eof

:claude_login
REM Note: this re-prompts even if already logged in. Use `claude-status`
REM to check without re-prompting.
docker run --rm -it %HARDENING% %VOLUMES% %ENVARGS% %IMAGE_NAME% claude login
goto :eof

:claude_status
REM Check whether Claude Code already has valid credentials.
REM Does not re-prompt or re-authenticate.
docker run --rm %HARDENING% %VOLUMES% %ENVARGS% %IMAGE_NAME% claude auth status
goto :eof

:install_claude_skill
docker run --rm %HARDENING% %VOLUMES% %ENVARGS% %IMAGE_NAME% bash -c "mkdir -p ~/.hermes/skills && cp -r /opt/hermes-skills/claude_code ~/.hermes/skills/ && echo Installed Claude Code skill to ~/.hermes/skills/claude_code/"
goto :eof

:install_codex_skill
docker run --rm %HARDENING% %VOLUMES% %ENVARGS% %IMAGE_NAME% bash -c "mkdir -p ~/.hermes/skills && cp -r /opt/hermes-skills/codex ~/.hermes/skills/ && echo Installed Codex skill to ~/.hermes/skills/codex/"
goto :eof

:install_skills
docker run --rm %HARDENING% %VOLUMES% %ENVARGS% %IMAGE_NAME% bash -c "mkdir -p ~/.hermes/skills && cp -r /opt/hermes-skills/claude_code /opt/hermes-skills/codex ~/.hermes/skills/ && echo Installed Claude Code + Codex skills"
goto :eof

:setup
docker run --rm -it %HARDENING% %VOLUMES% %PORTS% %ENVARGS% %IMAGE_NAME% hermes setup
goto :eof

:gateway_setup
docker run --rm -it %HARDENING% %VOLUMES% %PORTS% %ENVARGS% %IMAGE_NAME% hermes gateway
goto :eof

:up
call :is_running
if !RUNNING! equ 1 (
    echo Container '%CONTAINER_NAME%' is already running. Use 'attach' or 'stop'.
    exit /b 1
)
docker run -d --name %CONTAINER_NAME% %HARDENING% %VOLUMES% %PORTS% %ENVARGS% %IMAGE_NAME% bash -c "(openai-oauth > /tmp/oauth.log 2>&1 &) && (hermes gateway start > /tmp/gateway.log 2>&1 &) && sleep infinity"
if !errorlevel! equ 0 (
    echo Container '%CONTAINER_NAME%' started in background.
    echo   Attach: run.bat attach
    echo   Logs:   run.bat logs
    echo   Stop:   run.bat stop
)
goto :eof

:attach
call :is_running
if !RUNNING! equ 0 (
    echo Container '%CONTAINER_NAME%' is not running. Start it with 'up'.
    exit /b 1
)
docker exec -it %CONTAINER_NAME% bash
goto :eof

:logs
call :is_running
if !RUNNING! equ 0 (
    echo Container '%CONTAINER_NAME%' is not running.
    exit /b 1
)
echo === OAuth proxy log ===
docker exec %CONTAINER_NAME% cat /tmp/oauth.log 2>nul
echo.
echo === Gateway log ===
docker exec %CONTAINER_NAME% cat /tmp/gateway.log 2>nul
echo.
echo === Container log ===
docker logs --tail 50 %CONTAINER_NAME%
goto :eof

:stop
call :is_running
if !RUNNING! equ 1 (
    docker stop %CONTAINER_NAME%
    docker rm %CONTAINER_NAME% 2>nul
    echo Stopped.
) else (
    echo Not running.
)
goto :eof

:run
docker run --rm -it %HARDENING% %VOLUMES% %PORTS% %ENVARGS% %IMAGE_NAME% bash -c "(openai-oauth &) && sleep 2 && hermes"
goto :eof

:start
docker run --rm -it %HARDENING% %VOLUMES% %PORTS% %ENVARGS% %IMAGE_NAME%
goto :eof

:noshield
echo WARNING: No firewall, no hardening (DEBUG ONLY)
docker run --rm -it --entrypoint /bin/bash %VOLUMES% %ENVARGS% %IMAGE_NAME%
goto :eof

REM Helper: set RUNNING=1 if container is up, else 0
:is_running
set RUNNING=0
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%CONTAINER_NAME%"') do set RUNNING=1
goto :eof

:help
echo Usage: %~nx0 ^<command^>
echo.
echo Project:
echo   init ^<name^>     Create or select a project folder (auto-added to .gitignore)
echo.
echo Setup:
echo   build                 Build the Docker image
echo   login                 Codex OAuth login (ChatGPT Pro)
echo   claude-login          Claude Code OAuth login (always re-prompts)
echo   claude-status         Check Claude Code auth status (no re-prompt)
echo   install-claude-skill  Copy Claude Code skill into Hermes skills dir
echo   install-codex-skill   Copy Codex skill into Hermes skills dir
echo   install-skills        Install both delegation skills (Claude + Codex)
echo   setup                 Hermes setup wizard
echo   gateway-setup         Configure Discord/Slack gateway
echo.
echo Long-running:
echo   up              Start container in background (OAuth proxy + Gateway)
echo   attach          Open shell in running container
echo   logs            Show gateway and OAuth proxy logs
echo   stop            Stop the running container
echo.
echo One-shot:
echo   run             Run hermes interactively (proxy auto-started)
echo   start           Interactive shell
echo   noshield        DEBUG: shell without firewall
exit /b 1
