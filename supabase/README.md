# RuangKepo Supabase backend

This directory contains the SQL schema and RPC functions for the current static-site MVP.

## Current setup

- Supabase project: `ruangkepo` (project ref `odcqbkfgdqjtywyxaatc`), region Singapore.
- `schema.sql` has been applied to the project.
- The static frontend calls the Supabase REST RPC endpoint using the publishable key. Never place a secret/service-role key in browser code or GitHub.
- Kotak Rahasia supports creating a box, sending anonymous messages from a shared link, and reading messages with the owner's token.
- Ujian Bestie supports creating a quiz, sharing a public participant link, submitting answers, and reading results with the owner's token.
- Radar Kecocokan and Cek Identitas remain client-side entertainment features.

## RPC functions

- `create_secret_box()` returns a box UUID and a one-time owner token.
- `send_secret_message(p_box_id, p_body, p_sender_name)` stores a message for a box.
- `read_secret_messages(p_box_id, p_owner_token)` validates the owner token before returning messages.
- `create_bestie_quiz(p_title, p_questions)` creates a quiz and returns its owner token.
- `get_bestie_quiz(p_quiz_id)` returns public questions without correct answers.
- `submit_bestie_quiz(p_quiz_id, p_participant_name, p_answers)` scores answers in the database.
- `read_bestie_results(p_quiz_id, p_owner_token)` validates the owner token before returning submissions.

## Before a broad public launch

- Add server-side rate limiting and anti-spam protections, especially for anonymous message submission and quiz creation.
- Test abuse controls, owner-token handling, error states, and the complete browser flow on desktop and mobile.
- Owner tokens are credentials. They are stored in the browser's local storage by this MVP; clearing browser data can lose access to the owner's inbox/results. Do not share owner tokens.
- This is a lightweight MVP, not a fully moderated or abuse-resistant public service.
