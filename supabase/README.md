# RuangKepo Supabase foundation

This directory contains the initial SQL schema and RPC layer for the Supabase-backed prototype.

## Apply it

1. Create a Supabase project in your own dashboard.
2. Open **SQL Editor** in that project.
3. Open `schema.sql` from this directory, copy the complete contents, paste into SQL Editor, and run it.
4. If the SQL Editor reports an error, stop and inspect the first error before running modified SQL.
5. Keep the project URL and publishable key for later frontend integration. Never put a Supabase secret/service-role key in browser code or GitHub.

## RPC functions created

- `create_secret_box()` returns a box UUID and a one-time owner token.
- `send_secret_message(p_box_id, p_body, p_sender_name)` stores a message for a box.
- `read_secret_messages(p_box_id, p_owner_token)` checks the owner token before returning messages.
- `create_bestie_quiz(p_title, p_questions)` creates a quiz and returns its owner token.
- `get_bestie_quiz(p_quiz_id)` returns public questions without correct answers.
- `submit_bestie_quiz(p_quiz_id, p_participant_name, p_answers)` scores answers in the database.
- `read_bestie_results(p_quiz_id, p_owner_token)` checks the owner token before returning submissions.

## Important status

This file only creates database objects. It does not create a Supabase project, execute itself in Supabase, deploy the frontend, or connect `index.html` to these RPC functions. Those steps must happen separately. Before public launch, add rate limiting / abuse controls and test all authorization paths. Owner tokens are credentials: save them securely and do not share them.
