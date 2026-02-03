@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo Initializing git repository...
git init

echo.
echo Adding files...
git add .gitignore interconnected-conversations-design.md
git add interconnected-conversations-design.md

echo.
echo Committing...
git commit -m "Initial commit: Add interconnected conversations design document"

echo.
echo Creating GitHub repository convograph...
gh repo create convograph --public --source=. --remote=origin --push

echo.
echo Done!
pause
