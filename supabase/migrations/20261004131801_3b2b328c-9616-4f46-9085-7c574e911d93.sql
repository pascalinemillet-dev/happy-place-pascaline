ALTER TABLE public.submissions ADD COLUMN attachment_path text, ADD COLUMN attachment_name text;

CREATE OR REPLACE FUNCTION private.check_submission_attachment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NEW.attachment_path IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.attachment_path IS DISTINCT FROM OLD.attachment_path)
     AND NOT private.is_admin()
     AND split_part(NEW.attachment_path, '/', 1) <> coalesce(auth.uid()::text, '') THEN
    RAISE EXCEPTION 'Pièce jointe invalide';
  END IF;
  IF NEW.attachment_path IS NULL THEN NEW.attachment_name := NULL; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER check_submission_attachment BEFORE INSERT OR UPDATE ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.check_submission_attachment();

CREATE POLICY "Allowed users upload own submission PDF" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'submission-attachments'
  AND private.is_allowed()
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND lower(storage.extension(name)) = 'pdf'
);

CREATE POLICY "Reviewers and owner read submission PDF" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'submission-attachments'
  AND (
    private.is_admin()
    OR (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.submissions s
      WHERE s.attachment_path = storage.objects.name
        AND private.current_app_role() = 'manager'::public.app_role
        AND private.can_review_team(s.team)
    )
  )
);

CREATE POLICY "Admins delete submission PDF" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'submission-attachments' AND private.is_admin());