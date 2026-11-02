# RuangKepo Supabase backend

This directory contains the static site's database schema and RPC functions. The browser uses only the project's publishable key and calls validated RPC functions; it must never contain a service-role or Supabase secret key.

## Base schema

`schema.sql` defines the original Kotak Rahasia and Ujian Bestie tables and RPC functions. The base tables have RLS enabled and direct browser table privileges revoked. Public interactions use `SECURITY DEFINER` RPCs that validate input and owner tokens.

The live project ref is `odcqbkfgdqjtywyxaatc` (Singapore). **The database was inactive at the 2 November 2026 audit, so its current schema could not be queried.** Do not assume that the checked-in SQL has been applied to the currently inaccessible database.

## RPC functions

Base functions:
- `create_secret_box()` creates a private box and returns a one-time owner token.
- `send_secret_message(p_box_id, p_body, p_sender_name)` stores a message.
- `read_secret_messages(p_box_id, p_owner_token)` validates the owner token before returning messages.
- `create_bestie_quiz(p_title, p_questions)` creates a quiz and returns its owner token.
- `get_bestie_quiz(p_quiz_id)` returns public questions without correct answers.
- `submit_bestie_quiz(p_quiz_id, p_participant_name, p_answers)` scores answers in the database.
- `read_bestie_results(p_quiz_id, p_owner_token)` validates the owner token before returning submissions.

## Kotak Suara add-on — prepared, not applied

The UI and base SQL were out of sync: the UI called four voice-box RPCs that were not present in the original schema. The audit branch adds:

- `create_voice_box(p_title, p_owner_papers)` creates a box and stores exactly five owner-written papers.
- `submit_voice_paper(p_box_id, p_body, p_sender_name)` accepts up to five friend submissions per box.
- `read_voice_papers(p_box_id, p_owner_token)` returns paper metadata, but hides the body of every paper until it has been drawn.
- `draw_voice_paper(p_box_id, p_owner_token)` verifies the owner token, requires exactly ten papers (five owner + five friends), and atomically draws one remaining paper.

The migration is `migrations/20261102090000_add_voice_box_rpc.sql`. The audit branch also updates the frontend to require five owner texts, collect five friend submissions, and enable the draw action only when all ten are present.

**Important:** the migration is only committed on `audit/quality-security-2026-11`; it has not been applied to Supabase because the project is inactive. No database data or production configuration was changed.

## Before public launch

- Restore the Supabase project without pausing another project or upgrading the plan until the owner explicitly chooses an option.
- Apply and test the voice-box migration after the project is active and a database backup/restore point is confirmed.
- Test all RPCs, owner-token checks, concurrent draws, the five-friend submission cap, and that undrawn bodies are not returned.
- Add a suitable rate limit for anonymous box creation and message submission before a broad public launch.
- Test the full browser flow on desktop and mobile.

Owner tokens are credentials. The MVP stores owner tokens in browser local storage; clearing browser data may remove access to the owner's inbox/results. Never share owner tokens. This is a lightweight MVP, not a fully moderated or abuse-resistant public service.
