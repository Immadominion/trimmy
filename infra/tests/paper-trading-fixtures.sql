-- Dedicated nonprivileged role for the exclusively owned paper integration test.
CREATE ROLE trimmy_paper_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_paper_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_paper_test_app;
GRANT SELECT, INSERT ON trimmy.paper_accounts TO trimmy_paper_test_app;
GRANT UPDATE (cash_micros, revision, updated_at) ON trimmy.paper_accounts TO trimmy_paper_test_app;
GRANT SELECT, INSERT ON trimmy.paper_positions TO trimmy_paper_test_app;
GRANT UPDATE (symbol, quantity_micros, cost_basis_micros, realized_gain_micros,
  locked_gain_micros, last_order_revision, updated_at) ON trimmy.paper_positions TO trimmy_paper_test_app;
GRANT SELECT, INSERT ON trimmy.paper_order_previews TO trimmy_paper_test_app;
GRANT UPDATE (state, committed_at) ON trimmy.paper_order_previews TO trimmy_paper_test_app;
GRANT SELECT, INSERT ON trimmy.paper_orders TO trimmy_paper_test_app;
GRANT SELECT, INSERT ON trimmy.paper_cash_ledger TO trimmy_paper_test_app;
GRANT EXECUTE ON FUNCTION trimmy.paper_desk_reset(uuid, uuid, text, bigint)
  TO trimmy_paper_test_app;
