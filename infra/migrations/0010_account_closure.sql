-- Apply as the original migration owner after 0009. Until now an account could
-- be created but never closed: `users.status` has always allowed 'closed', and
-- practice_find_account/practice_account_exists have always excluded a closed
-- account, but nothing could ever set it, so there was no way for a person to
-- stop their account being usable.
--
-- The serving role deliberately has no privilege on trimmy.users and must keep
-- none, so closure goes through a definer function that can only ever close the
-- one account named by the verified transaction scope.
--
-- Closing an account is a lockout, not an erasure. Saved practice history,
-- receipts, watchlists and invitations remain exactly as they were, because
-- this schema treats them as immutable history and grants no DELETE anywhere.
-- Erasing or anonymising those records is a separate reviewed decision and this
-- migration does not perform it.
BEGIN;

-- Account status changes are significant, so they join the audited tables.
-- record_change() is already definer-rights, so the row is recorded even though
-- no runtime role may read or write audit_events.
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE ON trimmy.users
  FOR EACH ROW EXECUTE FUNCTION trimmy.record_change();

-- Closes only the account in the current transaction scope, which the API sets
-- from a verified token. It takes no argument precisely so that no caller can
-- name a different account. Returns true when this call performed the closure
-- and false when the account was already closed.
CREATE FUNCTION trimmy.practice_close_current_account() RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE scoped_user uuid := trimmy.practice_current_user();
DECLARE affected integer;
BEGIN
  IF scoped_user IS NULL THEN
    RAISE EXCEPTION 'An account scope is required to close an account'
      USING ERRCODE = '22023';
  END IF;
  UPDATE trimmy.users SET status = 'closed'
    WHERE id = scoped_user AND status <> 'closed';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected = 0 THEN
    -- Either already closed, or no such account. Both mean "nothing to do".
    RETURN false;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.practice_close_current_account() FROM PUBLIC;

-- Deployment grants, with the provisioned runtime role substituted, are applied
-- separately by tool/runtime/apply-migrations.mjs:
--   GRANT EXECUTE ON FUNCTION trimmy.practice_close_current_account()
--     TO trimmy_practice_runtime;
-- This adds no table privilege on trimmy.users and no financial privilege. The
-- runtime role still cannot read or write users rows directly.

INSERT INTO trimmy.schema_migrations(version) VALUES ('0010_account_closure');
COMMIT;
