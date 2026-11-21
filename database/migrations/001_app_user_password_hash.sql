BEGIN;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS password_hash TEXT;

-- Older catalog seeds inserted explicit user IDs without advancing BIGSERIAL.
-- ALTER holds the table lock through COMMIT. Never rewind an active sequence.
SELECT setval('app_user_user_id_seq', max(user_id), true)
FROM app_user, app_user_user_id_seq
HAVING max(user_id) >= max(last_value)
   AND (max(user_id) > max(last_value) OR NOT bool_and(is_called));
COMMIT;
