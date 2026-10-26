ALTER TABLE public.news ADD COLUMN author_email text;

CREATE OR REPLACE FUNCTION private.set_news_author_email()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NEW.author_email IS NULL THEN
    NEW.author_email := lower(auth.jwt() ->> 'email');
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER set_news_author_email
BEFORE INSERT ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_news_author_email();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  RETURN OLD;
END $$;

CREATE TRIGGER anonymize_removed_user
AFTER DELETE ON public.allowed_users
FOR EACH ROW EXECUTE FUNCTION private.anonymize_removed_user();