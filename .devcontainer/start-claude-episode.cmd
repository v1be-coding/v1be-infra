@echo off
rem Starts Claude Code inside the dev container, in one episode's repo, so that
rem repo's .claude folder loads: its commands, skills and git guardrail. It uses
rem the episode service, which mounts only the episode repos and its own Claude
rem config, so the session can't read the workspace's docs/ or transcripts.
rem Usage: start-claude-episode.cmd [repo], default episode-template. A Desktop
rem shortcut to this file opens the template; add the repo name to its target
rem for an episode.
title V1be Claude - EPISODE - CONTAINER
cd /d "%~dp0"

set "REPO=%~1"
if "%REPO%"=="" set "REPO=episode-template"
echo %REPO%| findstr /r /x "[a-z0-9][a-z0-9-]*" >nul
if errorlevel 1 (
  echo "%REPO%" isn't a repo name. Use lowercase letters, digits and dashes.
  pause
  exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
  echo Docker Desktop isn't running. Start it, wait until it's ready, then try again.
  pause
  exit /b 1
)

rem Warn when the volume holds a repo that isn't an episode, since this session
rem could read it. A warning only: press a key to start anyway.
for %%I in ("%CD%\..") do set "INFRA=%%~fI"
docker compose run --rm -v "%CD%\check-episodes-volume.sh:/tmp/check-episodes-volume.sh:ro" -v "%INFRA%\stacks\episodes.tfvars:/tmp/episodes.tfvars:ro" episode bash /tmp/check-episodes-volume.sh /tmp/episodes.tfvars /workspaces/v1be/episodes
if errorlevel 1 pause

docker compose run --rm -w "/workspaces/v1be/episodes/%REPO%" episode claude
if errorlevel 1 (
  echo If the folder was missing, clone the repo into /workspaces/v1be/episodes first.
  pause
)
