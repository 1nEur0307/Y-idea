# Autumn Job Tracker

A lightweight Chinese job-hunt company tracker for autumn campus recruiting.

## Features

- Local browser storage with add/edit/delete records
- Recruiting status, salary, probation salary and length, role content, location, working hours, company nature, insurance and housing-fund details
- Search, filters, sorting, CSV import/export
- Optional screenshot-to-form AI extraction through a local PowerShell service

## AI setup

Run `start-ai-recognition.bat` on Windows, enter your OpenAI API key when prompted, and keep the window open while using recognition. The key is not written to disk.

Data is stored in browser local storage. Export CSV backups regularly.
