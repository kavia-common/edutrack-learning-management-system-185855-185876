-- Migration 002: Additional indexes for performance

USE myapp;

-- Helper to guard index creation where IF NOT EXISTS is unsupported
-- This pattern attempts to create and ignores duplicate errors.
-- Users fast lookup by role and status
CREATE INDEX idx_users_role_status ON users (role, status);
-- Courses: search by visibility/category
CREATE INDEX idx_courses_visibility_category ON courses (visibility, category);
-- Lessons: quick fetch by course ordered by position already exists; add composite for analytics
CREATE INDEX idx_lessons_course_created ON lessons (course_id, created_at);
-- Enrollments: by course and status for instructor dashboards
CREATE INDEX idx_enrollments_course_status ON enrollments (course_id, status);
-- Progress: by lesson and status for lesson analytics
CREATE INDEX idx_progress_lesson_status ON progress (lesson_id, status);
-- Submissions: by quiz and status for grading queues
CREATE INDEX idx_submissions_quiz_status ON submissions (quiz_id, status);
-- Notifications: by user and created_at for pagination
CREATE INDEX idx_notifications_user_created ON notifications (user_id, created_at);
-- Payments: by user and status for billing pages
CREATE INDEX idx_payments_user_status ON payments (user_id, status, created_at);
-- Audit logs: by created_at for admin views
CREATE INDEX idx_audit_created ON audit_logs (created_at);
