-- Run history. Every refresh writes one row to history.run_log and a snapshot of the key numbers, so you can see
-- how the data and the problem count changed from run to run. dbt never touches this schema. Safe to run again.
create schema if not exists history;

create table if not exists history.run_log (
    run_id        bigint generated always as identity primary key,
    started_at    timestamptz not null default now(),
    report_date   date,
    dbt_pass      integer,
    dbt_warn      integer,
    dbt_error     integer,
    note          text
);

create table if not exists history.table_rowcount (
    run_id      bigint not null references history.run_log(run_id) on delete cascade,
    table_name  text   not null,
    row_count   bigint not null,
    primary key (run_id, table_name)
);

create table if not exists history.problem_count (
    run_id     bigint not null references history.run_log(run_id) on delete cascade,
    test_name  text   not null,
    failures   integer not null,
    primary key (run_id, test_name)
);

-- the state of every water bill at each run (what was overdue when)
create table if not exists history.water_bill_status (
    run_id          bigint not null references history.run_log(run_id) on delete cascade,
    water_bill_id   text   not null,
    address_raw     text,
    amount          numeric,
    follow_up_status text,
    days_past_due   integer,
    primary key (run_id, water_bill_id)
);

-- the state of every parking contract at each run
create table if not exists history.parking_status (
    run_id            bigint not null references history.run_log(run_id) on delete cascade,
    parking_lease_id  text   not null,
    address_raw       text,
    contract_status   text,
    contract_end_date date,
    primary key (run_id, parking_lease_id)
);
