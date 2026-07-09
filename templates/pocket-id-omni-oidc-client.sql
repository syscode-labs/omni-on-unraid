-- Pocket-ID OIDC client state required by Omni.
-- Omni is a confidential OIDC client and does not use PKCE for CLI public-key auth.
UPDATE oidc_clients
SET
  name = 'Omni',
  callback_urls = '["https://omni.example.internal/oidc/consume"]'::jsonb,
  logout_callback_urls = '["https://omni.example.internal/"]'::jsonb,
  is_public = false,
  pkce_enabled = false
WHERE id = 'omni';

DO $$
BEGIN
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pocket-ID OIDC client % does not exist. Create it once with the client secret, then apply this file.', 'omni';
  END IF;
END $$;
