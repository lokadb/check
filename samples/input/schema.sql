CREATE ROLE app LOGIN PASSWORD 'app';
CREATE DATABASE badapp;
\c badapp
CREATE TABLE organizations (id bigserial PRIMARY KEY, name text NOT NULL);
CREATE TABLE users (id bigserial PRIMARY KEY, organization_id bigint NOT NULL REFERENCES organizations, email text NOT NULL UNIQUE,
  invite_no int GENERATED ALWAYS AS IDENTITY);
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE TABLE documents (id bigserial PRIMARY KEY, organization_id bigint NOT NULL REFERENCES organizations, slug text NOT NULL,
  UNIQUE (organization_id, slug), UNIQUE (organization_id, id));
CREATE VIEW document_counts AS SELECT organization_id, count(*) FROM documents GROUP BY 1;
CREATE FUNCTION touch() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE TRIGGER documents_touch BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION touch();
GRANT SELECT ON documents TO app;
CREATE TABLE document_versions (id bigserial PRIMARY KEY, document_id bigint, content text);
CREATE TABLE attachments (id numeric(26,0) PRIMARY KEY, organization_id bigint NOT NULL,
  document_org bigint NOT NULL, document_id bigint NOT NULL, FOREIGN KEY (document_org, document_id) REFERENCES documents (organization_id, id));
INSERT INTO organizations (name) VALUES ('A'), ('B');
INSERT INTO documents (organization_id, slug) VALUES (1, 'a'), (2, 'b');
INSERT INTO document_versions (document_id, content) VALUES (1, 'ok'), (99, 'lost'), (NULL, 'lost');

\c postgres
CREATE DATABASE chat;
\c chat
CREATE TABLE accounts (id bigserial PRIMARY KEY, name text NOT NULL);
CREATE TABLE audit_log (id bigserial PRIMARY KEY, account_id bigint NOT NULL, action text NOT NULL);
CREATE TABLE conversations (id bigserial PRIMARY KEY, account_id bigint NOT NULL REFERENCES accounts, title text, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE messages (id bigserial PRIMARY KEY, account_id bigint NOT NULL REFERENCES accounts, conversation_id bigint, body text NOT NULL);
CREATE INDEX ON messages (conversation_id);
INSERT INTO accounts (name) VALUES ('A'), ('B');
INSERT INTO conversations (account_id, title) SELECT 1 + g % 2, 'c' || g FROM generate_series(1, 20) g;
INSERT INTO messages (account_id, conversation_id, body) SELECT c.account_id, c.id, 'm' || g FROM conversations c, generate_series(1, 5) g;
