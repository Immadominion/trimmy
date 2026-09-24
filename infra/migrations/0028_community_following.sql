BEGIN;
-- One-way following is distinct from the existing reciprocal friendships.
CREATE TABLE trimmy.community_follows (
  follower_id uuid NOT NULL REFERENCES trimmy.users(id),
  author_id uuid NOT NULL REFERENCES trimmy.users(id),
  notifications boolean NOT NULL DEFAULT true,
  followed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (follower_id, author_id),
  CHECK (follower_id <> author_id)
);
REVOKE ALL ON trimmy.community_follows FROM PUBLIC;
ALTER TABLE trimmy.community_follows ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION trimmy.community_follow_set(viewer uuid, target uuid, following boolean, notify boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE author uuid;
BEGIN
  IF viewer IS NULL OR trimmy.practice_current_user() IS DISTINCT FROM viewer
    OR following IS NULL OR notify IS NULL OR NOT EXISTS (
      SELECT 1 FROM trimmy.users u JOIN trimmy.practice_auth_identities a ON a.user_id=u.id
      WHERE u.id=viewer AND u.status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
  SELECT s.user_id INTO author FROM trimmy.social_profiles s JOIN trimmy.users u ON u.id=s.user_id
    WHERE s.public_id=target AND u.status='active';
  IF author IS NULL OR author=viewer THEN RAISE EXCEPTION 'AUTHOR_UNAVAILABLE'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.community-follow:' || viewer::text,0));
  IF NOT following THEN DELETE FROM trimmy.community_follows f WHERE f.follower_id=viewer AND f.author_id=author; RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM trimmy.social_blocks b WHERE b.state='active' AND
    (b.blocker_user_id,b.blocked_user_id) IN ((viewer,author),(author,viewer))) THEN RAISE EXCEPTION 'AUTHOR_UNAVAILABLE'; END IF;
  IF (SELECT count(*) FROM trimmy.community_follows f WHERE f.follower_id=viewer) >= 500
    AND NOT EXISTS (SELECT 1 FROM trimmy.community_follows f WHERE f.follower_id=viewer AND f.author_id=author)
    THEN RAISE EXCEPTION 'FOLLOW_LIMIT'; END IF;
  INSERT INTO trimmy.community_follows(follower_id,author_id,notifications) VALUES(viewer,author,notify)
    ON CONFLICT(follower_id,author_id) DO UPDATE SET notifications=excluded.notifications;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.community_follow_set(uuid,uuid,boolean,boolean) FROM PUBLIC;

CREATE FUNCTION trimmy.community_feed_get(viewer uuid, scope text, before_at timestamptz, before_id uuid)
RETURNS TABLE(reason_id uuid,social_id uuid,handle text,persona text,asset_id text,variant_mint text,symbol text,note text,saved_at timestamptz,following boolean,notifications boolean,is_viewer boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF viewer IS NULL OR trimmy.practice_current_user() IS DISTINCT FROM viewer OR scope IS NULL
    OR scope NOT IN ('everyone','following','notifications')
    OR (before_at IS NULL) <> (before_id IS NULL)
    OR NOT EXISTS (SELECT 1 FROM trimmy.users u JOIN trimmy.practice_auth_identities a ON a.user_id=u.id
      WHERE u.id=viewer AND u.status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
  RETURN QUERY SELECT r.public_id,s.public_id,p.handle,p.persona,r.asset_id,r.variant_mint::text,o.symbol,r.note,r.saved_at,
    f.author_id IS NOT NULL,coalesce(f.notifications,false),r.user_id=viewer
  FROM trimmy.career_trade_reasons r
  JOIN trimmy.users u ON u.id=r.user_id AND u.status='active'
  JOIN trimmy.practice_auth_identities a ON a.user_id=r.user_id
  JOIN trimmy.social_profiles s ON s.user_id=r.user_id
  JOIN trimmy.product_profiles p ON p.user_id=r.user_id
  JOIN trimmy.career_reason_privacy privacy ON privacy.user_id=r.user_id
  JOIN trimmy.paper_orders o ON o.id=r.order_id AND o.user_id=r.user_id
  JOIN trimmy.paper_accounts account ON account.user_id=r.user_id
  LEFT JOIN trimmy.community_follows f ON f.follower_id=viewer AND f.author_id=r.user_id
  WHERE privacy.visibility='everyone' AND privacy.configured
    AND o.account_revision>account.last_reset_revision
    AND (scope='everyone' OR f.author_id IS NOT NULL)
    AND (scope<>'notifications' OR (f.notifications AND r.saved_at>=f.followed_at))
    AND (before_at IS NULL OR (r.saved_at,r.public_id)<(before_at,before_id))
    AND NOT EXISTS (SELECT 1 FROM trimmy.social_reason_moderation m WHERE m.reason_public_id=r.public_id AND m.state='hidden')
    AND NOT EXISTS (SELECT 1 FROM trimmy.social_reason_reports report WHERE report.reporter_user_id=viewer AND report.reason_public_id=r.public_id)
    AND NOT EXISTS (SELECT 1 FROM trimmy.social_blocks b WHERE b.state='active' AND
      (b.blocker_user_id,b.blocked_user_id) IN ((viewer,r.user_id),(r.user_id,viewer)))
  ORDER BY r.saved_at DESC,r.public_id DESC LIMIT 21;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.community_feed_get(uuid,text,timestamptz,uuid) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES ('0028_community_following');
COMMIT;
