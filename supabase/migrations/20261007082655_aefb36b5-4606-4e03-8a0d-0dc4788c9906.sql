ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_rejection_note_max_500
  CHECK (rejection_note IS NULL OR char_length(btrim(rejection_note)) <= 500);