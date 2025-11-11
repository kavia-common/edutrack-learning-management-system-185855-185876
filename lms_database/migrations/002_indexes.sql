-- Migration 002: Additional indexes for performance (idempotent)

USE myapp;

-- Helper procedure to create an index only if it does not already exist
DROP PROCEDURE IF EXISTS create_index_if_absent;
DELIMITER //
CREATE PROCEDURE create_index_if_absent(
  IN p_schema VARCHAR(64),
  IN p_table VARCHAR(64),
  IN p_index VARCHAR(64),
  IN p_stmt TEXT
)
BEGIN
  DECLARE idx_count INT DEFAULT 0;
  SELECT COUNT(1)
    INTO idx_count
    FROM information_schema.statistics
   WHERE table_schema = p_schema
     AND table_name = p_table
     AND index_name = p_index;
  IF idx_count = 0 THEN
    SET @sql = p_stmt;
    PREPARE s FROM @sql;
    EXECUTE s;
    DEALLOCATE PREPARE s;
  END IF;
END //
DELIMITER ;

-- Define schema variable for reuse
SET @schema := DATABASE();

-- Users fast lookup by role and status
CALL create_index_if_absent(@schema, 'users', 'idx_users_role_status',
  'CREATE INDEX idx_users_role_status ON users (role, status)');

-- Courses: search by visibility/category
CALL create_index_if_absent(@schema, 'courses', 'idx_courses_visibility_category',
  'CREATE INDEX idx_courses_visibility_category ON courses (visibility, category)');

-- Lessons: composite for analytics
CALL create_index_if_absent(@schema, 'lessons', 'idx_lessons_course_created',
  'CREATE INDEX idx_lessons_course_created ON lessons (course_id, created_at)');

-- Enrollments: by course and status
CALL create_index_if_absent(@schema, 'enrollments', 'idx_enrollments_course_status',
  'CREATE INDEX idx_enrollments_course_status ON enrollments (course_id, status)');

-- Progress: by lesson and status
CALL create_index_if_absent(@schema, 'progress', 'idx_progress_lesson_status',
  'CREATE INDEX idx_progress_lesson_status ON progress (lesson_id, status)');

-- Submissions: by quiz and status
CALL create_index_if_absent(@schema, 'submissions', 'idx_submissions_quiz_status',
  'CREATE INDEX idx_submissions_quiz_status ON submissions (quiz_id, status)');

-- Notifications: by user and created_at
CALL create_index_if_absent(@schema, 'notifications', 'idx_notifications_user_created',
  'CREATE INDEX idx_notifications_user_created ON notifications (user_id, created_at)');

-- Payments: by user, status, created_at
CALL create_index_if_absent(@schema, 'payments', 'idx_payments_user_status',
  'CREATE INDEX idx_payments_user_status ON payments (user_id, status, created_at)');

-- Audit logs: by created_at
CALL create_index_if_absent(@schema, 'audit_logs', 'idx_audit_created',
  'CREATE INDEX idx_audit_created ON audit_logs (created_at)');

-- Cleanup helper
DROP PROCEDURE IF EXISTS create_index_if_absent;
