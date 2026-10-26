-- Version élèves : espaces de stockage utilisés par l'app (créés hors migrations dans l'app d'origine)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('submission-attachments', 'submission-attachments', false, 20971520, ARRAY['application/pdf']),
  ('news-media', 'news-media', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;
