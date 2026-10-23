-- Direct-entry tables for the rental warehouse.
-- Everything you type into Navicat goes into schema "entry". dbt never drops or rewrites this schema:
-- it only READS it and merges the rows with the rows that came from the Excel workbooks.
-- Safe to run again at any time (create ... if not exists). Run:  psql -d rental_dwh -f sql/10_entry_schema.sql

create schema if not exists entry;

-- ---------------------------------------------------------------------------------------------
-- helper: keep updated_at current and write every change to entry.audit_log
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.audit_log (
    audit_id     bigint generated always as identity primary key,
    changed_at   timestamptz not null default now(),
    changed_by   text        not null default current_user,
    table_name   text        not null,
    action       text        not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
    row_before   jsonb,
    row_after    jsonb
);

create or replace function entry.touch_and_audit() returns trigger language plpgsql as $$
begin
    if tg_op = 'DELETE' then
        insert into entry.audit_log(table_name, action, row_before) values (tg_table_name, 'DELETE', to_jsonb(old));
        return old;
    end if;
    new.updated_at := now();
    insert into entry.audit_log(table_name, action, row_before, row_after)
    values (tg_table_name, tg_op, case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
    return new;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. property: the master list. Every other entry table picks its address from here.
--    A house rented room by room: add one row per room, e.g. "12 Smith St Room 1".
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.property (
    address            text primary key check (address ~ '^[0-9]'),
    is_rented_by_room  boolean     not null default false,
    notes              text,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- 2. tenancy: one row per tenant per lease
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.tenancy (
    tenancy_entry_id    bigint generated always as identity primary key,
    address             text    not null references entry.property(address) on update cascade,
    tenant_name         text    not null check (btrim(tenant_name) <> ''),
    is_principal_tenant boolean not null default false,
    lease_type          text    not null default 'unspecified'
                        check (lease_type in ('whole_unit', 'room_share', 'studio', 'short_term', 'sublet', 'unspecified')),
    lease_start         date,
    lease_end           date,
    weekly_rent         numeric(9,2) check (weekly_rent >= 0),
    visa_expiry_date    date,
    notes               text,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    constraint tenancy_dates_ordered check (lease_end is null or lease_start is null or lease_end >= lease_start)
);

-- ---------------------------------------------------------------------------------------------
-- 3. rent_payment: money received from tenants (new: the workbooks only had monthly totals)
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.rent_payment (
    rent_payment_id  bigint generated always as identity primary key,
    address          text         not null references entry.property(address) on update cascade,
    paid_date        date         not null check (paid_date <= current_date + 1),
    amount           numeric(9,2) not null check (amount <> 0),   -- a refund is a negative amount
    method           text         not null default 'bank_transfer'
                     check (method in ('bank_transfer', 'cash', 'rmb_transfer', 'other')),
    received_by      text,
    notes            text,
    created_at       timestamptz  not null default now(),
    updated_at       timestamptz  not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- 4. water_bill
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.water_bill (
    water_bill_entry_id     bigint generated always as identity primary key,
    address                 text         not null references entry.property(address) on update cascade,
    period_start            date,
    period_end              date,
    amount                  numeric(9,2) not null check (amount >= 0),
    has_water_bill_copy     boolean      not null default false,
    company_paid_date       date,
    invoice_sent_date       date,
    invoice_sent_by         text,
    settled_in_exit_report  boolean      not null default false,
    tenant_paid_date        date,
    notes                   text,
    created_at              timestamptz  not null default now(),
    updated_at              timestamptz  not null default now(),
    constraint water_period_ordered check (period_end is null or period_start is null or period_end >= period_start),
    constraint water_invoice_needs_company_payment check (invoice_sent_date is null or company_paid_date is not null)
);

-- ---------------------------------------------------------------------------------------------
-- 5. utility_bill (electricity / gas)
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.utility_bill (
    utility_bill_entry_id bigint generated always as identity primary key,
    address               text not null references entry.property(address) on update cascade,
    bill_type             text not null check (bill_type in ('electricity', 'gas', 'electricity_and_gas')),
    period_start          date,
    period_end            date,
    due_date              date,
    amount                numeric(9,2) check (amount >= 0),
    invoice_sent_date     date,
    invoice_sent_by       text,
    payment_check_date    date,
    is_not_set_up         boolean not null default false,
    notes                 text,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    constraint utility_period_ordered check (period_end is null or period_start is null or period_end >= period_start)
);

-- ---------------------------------------------------------------------------------------------
-- 6. inspection_notice (routine, fire safety, other)
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.inspection_notice (
    inspection_entry_id bigint generated always as identity primary key,
    address             text not null references entry.property(address) on update cascade,
    notice_type         text not null check (notice_type in ('routine', 'fire', 'other')),
    notice_date         date not null,           -- the day of the inspection
    time_text           text,
    notice_given_date   date,                    -- the day the tenant was told
    category            text,
    sent_by             text,
    notice_sent         boolean not null default false,
    pre_check_by        text,
    attended_by         text,
    completion_text     text,
    is_completed        boolean not null default false,
    follow_up_by        text,
    notes               text,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    constraint notice_given_before_inspection check (notice_given_date is null or notice_given_date <= notice_date)
);

-- ---------------------------------------------------------------------------------------------
-- 7. special_term: a special clause agreed with a tenant
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.special_term (
    special_term_entry_id bigint generated always as identity primary key,
    address               text not null references entry.property(address) on update cascade,
    term_text             text not null check (btrim(term_text) <> ''),
    status_text           text,                  -- how it was carried out; empty = not recorded yet
    recorded_by           text,
    recorded_date         date,
    notes                 text,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- 8. parking_lease: one parking space or garage
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.parking_lease (
    parking_entry_id  bigint generated always as identity primary key,
    address           text not null references entry.property(address) on update cascade,
    space_label       text not null,             -- e.g. "P12" or "Garage 3"
    space_kind        text not null default 'parking_space' check (space_kind in ('parking_space', 'garage')),
    contract_end_date date,                      -- empty = nobody is renting it
    notes             text,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    unique (address, space_label)
);

-- ---------------------------------------------------------------------------------------------
-- 9. moving_job and its items
-- ---------------------------------------------------------------------------------------------
create table if not exists entry.moving_job (
    moving_job_entry_id bigint generated always as identity primary key,
    address             text not null references entry.property(address) on update cascade,
    job_date            date not null,
    rooms_text          text,
    bedrooms            integer check (bedrooms >= 0),
    stairs_text         text,
    work_hours          numeric(5,2) check (work_hours >= 0),
    crew_text           text,
    note_text           text,
    problem_text        text,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);

create table if not exists entry.moving_job_item (
    moving_job_entry_id bigint  not null references entry.moving_job(moving_job_entry_id) on delete cascade,
    item_code           text    not null check (item_code ~ '^[a-z_]+$'),   -- e.g. fridge, double_bed, tv_table
    quantity            numeric not null check (quantity >= 0),
    primary key (moving_job_entry_id, item_code)
);

-- ---------------------------------------------------------------------------------------------
-- triggers: updated_at + audit on every entry table
-- ---------------------------------------------------------------------------------------------
do $$
declare t text;
begin
    foreach t in array array['property','tenancy','rent_payment','water_bill','utility_bill',
                             'inspection_notice','special_term','parking_lease','moving_job','moving_job_item']
    loop
        execute format('drop trigger if exists trg_touch_audit on entry.%I', t);
        if t = 'moving_job_item' then
            -- no updated_at column on this one: audit only
            execute 'create or replace function entry.audit_only() returns trigger language plpgsql as $f$
                     begin
                       if tg_op = ''DELETE'' then
                         insert into entry.audit_log(table_name, action, row_before) values (tg_table_name, ''DELETE'', to_jsonb(old)); return old;
                       end if;
                       insert into entry.audit_log(table_name, action, row_before, row_after)
                       values (tg_table_name, tg_op, case when tg_op = ''UPDATE'' then to_jsonb(old) end, to_jsonb(new));
                       return new;
                     end $f$';
            execute format('create trigger trg_touch_audit after insert or update or delete on entry.%I
                            for each row execute function entry.audit_only()', t);
        else
            execute format('create trigger trg_touch_audit before insert or update or delete on entry.%I
                            for each row execute function entry.touch_and_audit()', t);
        end if;
    end loop;
end $$;
