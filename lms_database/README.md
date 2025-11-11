# LMS Database (MySQL)

This directory contains the MySQL schema, migrations, seed data, and helper scripts for the LMS.

Key details:
- DB name: myapp
- App user: appuser (password: dbuser123)
- Port: 5000
- Connection helper: see db_connection.txt after startup

Contents
- schema.sql: Full normalized LMS schema (users, courses, lessons, resources, quizzes, questions, question_options, enrollments, progress, submissions, submission_answers, notifications, payments, audit_logs).
- migrations/
  - 001_init.sql: Applies the schema.
  - 002_indexes.sql: Adds extra composite indexes for performance.
- seed.sql: Minimal realistic seed data (admin, instructor, student, sample course with lessons and a quiz).
- startup.sh: Starts MySQL, ensures app user and DB exist, auto-applies migrations and seed.
- backup_db.sh / restore_db.sh: Utility scripts for backups and restore.
- db_visualizer/: Simple Node viewer with env file generated on startup.

How to use
1) Start database and apply migrations/seed automatically:
   - Run: ./startup.sh
   - On success, a db_connection.txt file will be created with the exact mysql CLI command
   - Migrations are applied in order from migrations/*.sql and tracked in myapp._migrations

2) Manual migration application (optional):
   - Use db_connection.txt command:
     - $(cat db_connection.txt) < migrations/001_init.sql
     - $(cat db_connection.txt) < migrations/002_indexes.sql

3) Apply seed data (optional if startup already ran):
   - $(cat db_connection.txt) < seed.sql

4) Backup and Restore:
   - Backup: ./backup_db.sh
   - Restore: ./restore_db.sh

Environment variables for integration
- The following variables are exported into db_visualizer/mysql.env after startup:
  - MYSQL_URL="mysql://localhost:5000/myapp"
  - MYSQL_USER="appuser"
  - MYSQL_PASSWORD="dbuser123"
  - MYSQL_DB="myapp"
  - MYSQL_PORT="5000"

Notes
- Do not hardcode credentials in application code. Use environment variables.
- The seed passwords are placeholders; the backend must manage secure hashing and authentication.
- The schema is designed for growth with proper FKs, uniqueness, and indexes for common access patterns.

Troubleshooting
- If startup reports MySQL already running, migrations and seed will still be attempted.
- If db_connection.txt exists, scripts prefer using it for SQL application.
