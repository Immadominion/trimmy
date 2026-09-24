-- Apply as the original migration owner after 0008. The invitations table has
-- existed since 0001 with its full state machine, and 0001's protect_invitation
-- trigger already enforces the legal transitions, version sequence, terminal
-- states and immutable terms. What was missing is access: the table had no
-- policies and no grants, so no application role could reach it at all.
--
-- This migration adds exactly two things. First, row security that lets the two
-- parties to an invitation see it, the sender and the addressed recipient, and
-- nobody else. Second, an actor rule that structural constraints cannot express:
-- only the sender may address, offer or cancel, and only the addressed person
-- may accept or decline.
--
-- Invitations remain unfunded. Accepting one records social intent only. It
-- moves no money, mints nothing and delivers no asset, and this migration adds
-- no privilege on any financial table.
BEGIN;

-- The account scope already used by the practice tables, named once so the
-- invitation policy and trigger cannot drift from it.
CREATE FUNCTION trimmy.practice_current_user() RETURNS uuid
LANGUAGE sql STABLE
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT nullif(current_setting('trimmy.practice_user_id', true), '')::uuid;
$$;
REVOKE ALL ON FUNCTION trimmy.practice_current_user() FROM PUBLIC;

-- Resolves the scoped account's own verified X subject. It is SECURITY DEFINER
-- so the runtime role never needs read access to the identity table itself, and
-- it can only ever return the caller's own subject.
CREATE FUNCTION trimmy.invitation_self_x_subject() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT identity.subject
    FROM trimmy.provider_identities identity
    JOIN trimmy.users account ON account.id = identity.user_id
   WHERE identity.user_id = trimmy.practice_current_user()
     AND identity.provider = 'x'
     AND account.status <> 'closed'
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION trimmy.invitation_self_x_subject() FROM PUBLIC;

-- Who may act, as opposed to what shape the row may take. 0001 already owns the
-- structural rules; this only binds each transition to the right account.
CREATE FUNCTION trimmy.scope_invitation_actor() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.sender_user_id IS DISTINCT FROM trimmy.practice_current_user() THEN
      RAISE EXCEPTION 'An invitation must be created by the scoped sender'
        USING ERRCODE = '23514', CONSTRAINT = 'invitation_sender_scope';
    END IF;
    IF NEW.recipient_subject IS NOT NULL OR NEW.recipient_user_id IS NOT NULL
        OR NEW.accepted_at IS NOT NULL THEN
      RAISE EXCEPTION 'A new invitation is not yet addressed or answered'
        USING ERRCODE = '23514', CONSTRAINT = 'invitation_initial_state';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.state IN ('accepted', 'declined') AND NEW.state <> OLD.state THEN
    -- Only the addressed person may answer, and answering binds their account.
    IF NEW.recipient_subject IS NULL
        OR NEW.recipient_subject IS DISTINCT FROM trimmy.invitation_self_x_subject()
        OR NEW.recipient_user_id IS DISTINCT FROM trimmy.practice_current_user() THEN
      RAISE EXCEPTION 'Only the addressed recipient may answer an invitation'
        USING ERRCODE = '23514', CONSTRAINT = 'invitation_recipient_scope';
    END IF;
  ELSIF NEW.state <> OLD.state AND NEW.state <> 'expired' THEN
    -- Addressing, offering and cancelling belong to the sender. Expiry is a
    -- fact about the clock rather than an act by either party.
    IF OLD.sender_user_id IS DISTINCT FROM trimmy.practice_current_user() THEN
      RAISE EXCEPTION 'Only the sender may address, offer or cancel an invitation'
        USING ERRCODE = '23514', CONSTRAINT = 'invitation_sender_scope';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.scope_invitation_actor() FROM PUBLIC;
CREATE TRIGGER scope_invitation_actor BEFORE INSERT OR UPDATE ON trimmy.invitations
  FOR EACH ROW EXECUTE FUNCTION trimmy.scope_invitation_actor();

-- 0001 enabled row security on this table; forcing it applies the policy to the
-- owner too, matching the practice tables.
ALTER TABLE trimmy.invitations FORCE ROW LEVEL SECURITY;

-- Exactly two parties can see an invitation. A recipient is recognised by the
-- X subject it was addressed to, so an offer is visible before that person has
-- ever linked an account, and by their user id once acceptance binds it.
CREATE POLICY invitation_party_scope ON trimmy.invitations
  USING (
    sender_user_id = trimmy.practice_current_user()
    OR recipient_user_id = trimmy.practice_current_user()
    OR (recipient_provider = 'x' AND recipient_subject IS NOT NULL
        AND recipient_subject = trimmy.invitation_self_x_subject()))
  WITH CHECK (
    sender_user_id = trimmy.practice_current_user()
    OR (recipient_provider = 'x' AND recipient_subject IS NOT NULL
        AND recipient_subject = trimmy.invitation_self_x_subject()));

REVOKE ALL ON TABLE trimmy.invitations FROM PUBLIC;

-- Deployment grants, with the provisioned runtime role substituted, are applied
-- separately by tool/runtime/apply-migrations.mjs:
--   GRANT SELECT ON trimmy.invitations TO trimmy_practice_runtime;
--   GRANT INSERT (id, sender_user_id, state, funding_kind, expires_at, version)
--     ON trimmy.invitations TO trimmy_practice_runtime;
--   GRANT UPDATE (state, recipient_provider, recipient_subject, recipient_handle_snapshot, recipient_user_id, accepted_at, version)
--     ON trimmy.invitations TO trimmy_practice_runtime;
-- The value-bearing columns asset_id and indicative_amount_raw are deliberately
-- left out, so the serving role cannot attach an amount to an invitation.
--   GRANT EXECUTE ON FUNCTION trimmy.practice_current_user(),
--     trimmy.invitation_self_x_subject() TO trimmy_practice_runtime;
-- Still no DELETE, no TRUNCATE and no financial-table privilege. The existing
-- preserve_history trigger from 0001 continues to reject deletes outright.

INSERT INTO trimmy.schema_migrations(version) VALUES ('0009_invitations');
COMMIT;
