@echo off
rem Starts Claude Code inside the dev container. Double-click it, or use the Desktop shortcut.
title V1be Claude - CONTAINER
cd /d "%~dp0"

docker info >nul 2>&1
if errorlevel 1 (
  echo Docker Desktop isn't running. Start it, wait until it's ready, then try again.
  pause
  exit /b 1
)

docker compose run --rm dev claude %*
if errorlevel 1 pause
