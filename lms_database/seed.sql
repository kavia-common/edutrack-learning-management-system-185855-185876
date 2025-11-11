-- Seed data for LMS (minimal realistic)
USE myapp;

-- Users (note: password_hash values are placeholders; backend should manage hashing)
INSERT INTO users (email, password_hash, full_name, role, status)
VALUES
('admin@example.com', '$2y$10$adminhashplaceholder', 'System Admin', 'admin', 'active'),
('instructor@example.com', '$2y$10$instructorhashplaceholder', 'Jane Instructor', 'instructor', 'active'),
('student@example.com', '$2y$10$studenthashplaceholder', 'John Student', 'student', 'active')
ON DUPLICATE KEY UPDATE full_name=VALUES(full_name), role=VALUES(role), status=VALUES(status);

-- Resolve user IDs
SET @admin_id = (SELECT id FROM users WHERE email='admin@example.com');
SET @instructor_id = (SELECT id FROM users WHERE email='instructor@example.com');
SET @student_id = (SELECT id FROM users WHERE email='student@example.com');

-- Sample Course
INSERT INTO courses (title, description, instructor_id, category, level, price_cents, visibility)
VALUES ('Intro to Modern Web Development', 'Learn the basics of HTML, CSS, JS, and React fundamentals.', @instructor_id, 'Web Development', 'beginner', 0, 'public')
ON DUPLICATE KEY UPDATE description=VALUES(description), instructor_id=VALUES(instructor_id);

-- Resolve course ID
SET @course_id = (SELECT id FROM courses WHERE title='Intro to Modern Web Development' AND instructor_id=@instructor_id LIMIT 1);

-- Lessons
INSERT INTO lessons (course_id, title, content, video_url, position, duration_seconds)
VALUES 
(@course_id, 'Welcome and Setup', 'Introduction to the course and environment setup.', 'https://videos.example.com/welcome.mp4', 1, 300),
(@course_id, 'HTML & CSS Basics', 'Learn structure and styling.', 'https://videos.example.com/html-css.mp4', 2, 900),
(@course_id, 'JavaScript Primer', 'Fundamentals of JavaScript.', 'https://videos.example.com/js-primer.mp4', 3, 1200)
ON DUPLICATE KEY UPDATE content=VALUES(content), video_url=VALUES(video_url), duration_seconds=VALUES(duration_seconds);

-- Resolve lesson IDs
SET @lesson1 = (SELECT id FROM lessons WHERE course_id=@course_id AND position=1);
SET @lesson2 = (SELECT id FROM lessons WHERE course_id=@course_id AND position=2);
SET @lesson3 = (SELECT id FROM lessons WHERE course_id=@course_id AND position=3);

-- Resources
INSERT INTO resources (lesson_id, resource_type, title, url)
VALUES
(@lesson1, 'link', 'Course Syllabus', 'https://example.com/syllabus.pdf'),
(@lesson2, 'pdf', 'HTML & CSS Cheatsheet', 'https://example.com/html-css-cheatsheet.pdf'),
(@lesson3, 'link', 'MDN JavaScript Guide', 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide')
ON DUPLICATE KEY UPDATE url=VALUES(url);

-- Enrollment for student
INSERT INTO enrollments (user_id, course_id, status)
VALUES (@student_id, @course_id, 'active')
ON DUPLICATE KEY UPDATE status='active';

-- Initial Progress
INSERT INTO progress (user_id, lesson_id, status, percent_complete, last_viewed_at)
VALUES
(@student_id, @lesson1, 'in_progress', 50, NOW()),
(@student_id, @lesson2, 'not_started', 0, NULL)
ON DUPLICATE KEY UPDATE status=VALUES(status), percent_complete=VALUES(percent_complete), last_viewed_at=VALUES(last_viewed_at);

-- Quiz for course
INSERT INTO quizzes (course_id, title, description, passing_score, time_limit_minutes)
VALUES (@course_id, 'Module 1 Quiz', 'Covers basics of HTML & CSS', 70, 15)
ON DUPLICATE KEY UPDATE description=VALUES(description), passing_score=VALUES(passing_score);

-- Resolve quiz ID
SET @quiz_id = (SELECT id FROM quizzes WHERE course_id=@course_id AND title='Module 1 Quiz' LIMIT 1);

-- Questions
INSERT INTO questions (quiz_id, question_text, question_type, position, points)
VALUES
(@quiz_id, 'HTML stands for?', 'single_choice', 1, 1),
(@quiz_id, 'CSS is used for?', 'single_choice', 2, 1),
(@quiz_id, 'Select valid CSS properties', 'multiple_choice', 3, 1)
ON DUPLICATE KEY UPDATE question_text=VALUES(question_text), question_type=VALUES(question_type);

-- Resolve question IDs
SET @q1 = (SELECT id FROM questions WHERE quiz_id=@quiz_id AND position=1);
SET @q2 = (SELECT id FROM questions WHERE quiz_id=@quiz_id AND position=2);
SET @q3 = (SELECT id FROM questions WHERE quiz_id=@quiz_id AND position=3);

-- Options
INSERT INTO question_options (question_id, option_text, is_correct, position)
VALUES
(@q1, 'HyperText Markup Language', 1, 1),
(@q1, 'HighText Machine Language', 0, 2),
(@q2, 'Styling web pages', 1, 1),
(@q2, 'Server-side scripting', 0, 2),
(@q3, 'color', 1, 1),
(@q3, 'fontsize', 0, 2),
(@q3, 'margin', 1, 3),
(@q3, 'padding', 1, 4)
ON DUPLICATE KEY UPDATE is_correct=VALUES(is_correct), position=VALUES(position);

-- Demo submission by student (submitted and passed)
INSERT INTO submissions (user_id, quiz_id, started_at, submitted_at, score, status)
VALUES (@student_id, @quiz_id, NOW(), NOW(), 100, 'passed');

SET @submission_id = LAST_INSERT_ID();

-- Submission answers
INSERT INTO submission_answers (submission_id, question_id, selected_option_id, is_correct)
VALUES
(@submission_id, @q1, (SELECT id FROM question_options WHERE question_id=@q1 AND is_correct=1 LIMIT 1), 1),
(@submission_id, @q2, (SELECT id FROM question_options WHERE question_id=@q2 AND is_correct=1 LIMIT 1), 1),
(@submission_id, @q3, NULL, NULL); -- multiple selected could be modeled with multiple rows; left null for demo

-- Notifications
INSERT INTO notifications (user_id, type, title, message, is_read)
VALUES
(@student_id, 'course', 'Welcome to the course!', 'Glad to have you in Intro to Modern Web Development.', 0),
(@instructor_id, 'enrollment', 'New enrollment', 'John Student enrolled in your course.', 0);

-- Payments (free course -> succeeded with 0)
INSERT INTO payments (user_id, course_id, amount_cents, currency, provider, provider_ref, status)
VALUES
(@student_id, @course_id, 0, 'USD', 'internal', 'FREE-ENROLL', 'succeeded')
ON DUPLICATE KEY UPDATE status='succeeded';

-- Audit logs
INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
VALUES
(@admin_id, 'CREATE_COURSE', 'course', @course_id, JSON_OBJECT('title','Intro to Modern Web Development')),
(@student_id, 'ENROLL', 'course', @course_id, JSON_OBJECT('status','active'));
