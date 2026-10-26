DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMENT ON FUNCTION private.notify_departure(uuid, text, text, date, text) IS 'Crée les alertes de départ même sans document joint (le bandeau informe alors simplement du départ).';