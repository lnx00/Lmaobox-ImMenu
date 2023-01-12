@echo off

node bundle.js
move /Y "ImMenu.lua" "%localappdata%"
pause