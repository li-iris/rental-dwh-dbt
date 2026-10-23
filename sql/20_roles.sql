-- Two database accounts for other people. Run once as the database owner (scripts/08_create_users.sh does it):
--   boss_entry    reads the finished tables (schema gold) and types data into schema entry. Cannot see raw data
--                 (bronze holds phone numbers and e-mail), cannot change or delete anything else.
--   report_viewer reads the finished tables only.
-- :boss_pw and :viewer_pw are passed in by the shell script.

select format('create role boss_entry login password %L', :'boss_pw')
 where not exists (select 1 from pg_roles where rolname = 'boss_entry') \gexec
select format('alter role boss_entry password %L', :'boss_pw') \gexec
select format('create role report_viewer login password %L', :'viewer_pw')
 where not exists (select 1 from pg_roles where rolname = 'report_viewer') \gexec
select format('alter role report_viewer password %L', :'viewer_pw') \gexec

select format('grant connect on database %I to boss_entry, report_viewer', current_database()) \gexec

-- finished tables: read only. dbt drops and recreates tables on every run, so default privileges are needed too.
grant usage on schema gold to boss_entry, report_viewer;
grant select on all tables in schema gold to boss_entry, report_viewer;
alter default privileges in schema gold grant select on tables to boss_entry, report_viewer;

-- direct entry: boss_entry may read and write the entry tables
grant usage on schema entry to boss_entry;
grant select, insert, update, delete on all tables in schema entry to boss_entry;
grant usage, select on all sequences in schema entry to boss_entry;
alter default privileges in schema entry grant select, insert, update, delete on tables to boss_entry;
alter default privileges in schema entry grant usage, select on sequences to boss_entry;
-- but the audit trail can only be added to, never edited
revoke update, delete on entry.audit_log from boss_entry;

-- run history: read only
grant usage on schema history to boss_entry, report_viewer;
grant select on all tables in schema history to boss_entry, report_viewer;
alter default privileges in schema history grant select on tables to boss_entry, report_viewer;

-- everything else (bronze, silver, dbt audit tables) stays invisible: no usage granted.
revoke all on schema public from boss_entry, report_viewer;
