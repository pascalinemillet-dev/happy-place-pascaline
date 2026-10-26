ALTER TABLE public.news ADD COLUMN IF NOT EXISTS image_path text;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS links jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION private.check_news_links()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, private AS $$
DECLARE _l jsonb; _url text; _label text;
BEGIN
  IF NEW.links IS NULL OR jsonb_typeof(NEW.links) <> 'array' THEN
    RAISE EXCEPTION 'Les liens doivent être une liste.' USING ERRCODE = '23514';
  END IF;
  IF jsonb_array_length(NEW.links) > 3 THEN
    RAISE EXCEPTION '3 liens maximum par actualité.' USING ERRCODE = '23514';
  END IF;
  FOR _l IN SELECT value FROM jsonb_array_elements(NEW.links) LOOP
    IF jsonb_typeof(_l) <> 'object' OR jsonb_typeof(_l->'url') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'Chaque lien doit avoir une adresse.' USING ERRCODE = '23514';
    END IF;
    _url := _l->>'url';
    IF _url !~* '^https?://[^\s]+$' THEN
      RAISE EXCEPTION 'Adresse de lien invalide : seules les adresses http:// ou https:// sont acceptées.' USING ERRCODE = '23514';
    END IF;
    IF char_length(_url) > 2000 THEN
      RAISE EXCEPTION 'Adresse de lien trop longue (2 000 caractères maximum).' USING ERRCODE = '23514';
    END IF;
    IF _l ? 'label' AND jsonb_typeof(_l->'label') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'Libellé de lien invalide.' USING ERRCODE = '23514';
    END IF;
    _label := _l->>'label';
    IF _label IS NOT NULL AND char_length(_label) > 80 THEN
      RAISE EXCEPTION 'Libellé de lien trop long (80 caractères maximum).' USING ERRCODE = '23514';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS check_news_links ON public.news;
CREATE TRIGGER check_news_links BEFORE INSERT OR UPDATE OF links ON public.news
FOR EACH ROW EXECUTE FUNCTION private.check_news_links();

CREATE OR REPLACE FUNCTION private.can_edit_news_media(_news_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT private.is_admin() OR EXISTS (
    SELECT 1 FROM public.news n
    WHERE n.id::text = _news_id
      AND private.current_app_role() = 'manager'
      AND n.status = 'brouillon'
      AND n.author_email = lower(auth.jwt() ->> 'email'))
$$;
REVOKE EXECUTE ON FUNCTION private.can_edit_news_media(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION private.can_edit_news_media(text) TO authenticated;

CREATE POLICY "News media read" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'news-media' AND private.is_allowed()
  AND EXISTS (SELECT 1 FROM public.news n WHERE n.id::text = (storage.foldername(name))[1]));

CREATE POLICY "News media insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'news-media' AND private.is_allowed()
  AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND private.can_edit_news_media((storage.foldername(name))[1]));

CREATE POLICY "News media update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'news-media' AND private.can_edit_news_media((storage.foldername(name))[1]))
WITH CHECK (bucket_id = 'news-media' AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND private.can_edit_news_media((storage.foldername(name))[1]));

CREATE POLICY "News media delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'news-media' AND private.can_edit_news_media((storage.foldername(name))[1]));