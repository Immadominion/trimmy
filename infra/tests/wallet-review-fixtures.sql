-- Committed grants for the private integration cluster's app role (mirrors the
-- deployment grants documented in migration 0007).
GRANT SELECT, INSERT ON trimmy.wallet_bindings TO trimmy_practice_test_app;
GRANT SELECT, INSERT, UPDATE ON trimmy.stock_order_reviews TO trimmy_practice_test_app;
