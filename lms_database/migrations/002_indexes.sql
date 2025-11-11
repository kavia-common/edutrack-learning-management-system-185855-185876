-- Migration 002: Additional indexes for performance

USE myapp;

-- Covering/index improvements beyond those defined inline

-- Users fast lookup by role and status
CREATE INDEX IF NOT EXISTS idx_users_role_status ON users (role, status);

-- Courses: search by visibility/category
CREATE INDEX IF NOT EXISTS idx_courses_visibility_category ON courses (visibility, category);

-- Lessons: quick fetch by course ordered by position already exists; add composite for analytics
CREATE INDEX IF NOT EXISTS idx_lessons_course_created ON lessons (course_id, created_at);

-- Enrollments: by course and status for instructor dashboards
CREATE INDEX IF NOT EXISTS idx_enrollments_course_status ON enrollments (course_id, status);

-- Progress: by lesson and status for lesson analytics
CREATE INDEX IF NOT EXISTS idx_progress_lesson_status ON progress (lesson_id, status);

-- Submissions: by quiz and status for grading queues
CREATE INDEX IF NOT EXISTS idx_submissions_quiz_status ON submissions (quiz_id, status);

-- Notifications: by user and created_at for pagination
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications (user_id, created_at);

-- Payments: by user and status for billing pages
CREATE INDEX IF NOT EXISTS idx_payments_user_status ON payments (user_id, status, created_at);

-- Audit logs: by created_at for admin views
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs (created_at);
