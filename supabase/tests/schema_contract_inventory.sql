\pset pager off

\echo ''
\echo '============================================================'
\echo '1. PUBLIC ENUM TYPES AND ALL ALLOWED VALUES'
\echo '============================================================'

select
  ns.nspname as enum_schema,
  typ.typname as enum_type,
  enum.enumsortorder as sort_order,
  enum.enumlabel as allowed_value
from pg_type as typ
join pg_enum as enum
  on enum.enumtypid = typ.oid
join pg_namespace as ns
  on ns.oid = typ.typnamespace
where ns.nspname = 'public'
order by
  typ.typname,
  enum.enumsortorder;


\echo ''
\echo '============================================================'
\echo '2. PUBLIC TABLE COLUMNS, TYPES, NULLABILITY AND DEFAULTS'
\echo '============================================================'

select
  cols.table_name,
  cols.ordinal_position,
  cols.column_name,
  cols.data_type,
  cols.udt_name,
  cols.is_nullable,
  cols.column_default
from information_schema.columns as cols
where cols.table_schema = 'public'
order by
  cols.table_name,
  cols.ordinal_position;


\echo ''
\echo '============================================================'
\echo '3. CHECK CONSTRAINTS'
\echo '============================================================'

select
  cls.relname as table_name,
  con.conname as constraint_name,
  pg_get_constraintdef(con.oid, true) as constraint_definition
from pg_constraint as con
join pg_class as cls
  on cls.oid = con.conrelid
join pg_namespace as ns
  on ns.oid = cls.relnamespace
where ns.nspname = 'public'
  and con.contype = 'c'
order by
  cls.relname,
  con.conname;


\echo ''
\echo '============================================================'
\echo '4. FOREIGN KEYS'
\echo '============================================================'

select
  source_table.relname as source_table,
  con.conname as constraint_name,
  pg_get_constraintdef(con.oid, true) as constraint_definition
from pg_constraint as con
join pg_class as source_table
  on source_table.oid = con.conrelid
join pg_namespace as source_schema
  on source_schema.oid = source_table.relnamespace
where source_schema.nspname = 'public'
  and con.contype = 'f'
order by
  source_table.relname,
  con.conname;


\echo ''
\echo '============================================================'
\echo '5. UNIQUE AND PRIMARY KEY CONSTRAINTS'
\echo '============================================================'

select
  cls.relname as table_name,
  con.conname as constraint_name,
  case con.contype
    when 'p' then 'PRIMARY KEY'
    when 'u' then 'UNIQUE'
  end as constraint_type,
  pg_get_constraintdef(con.oid, true) as constraint_definition
from pg_constraint as con
join pg_class as cls
  on cls.oid = con.conrelid
join pg_namespace as ns
  on ns.oid = cls.relnamespace
where ns.nspname = 'public'
  and con.contype in ('p', 'u')
order by
  cls.relname,
  constraint_type,
  con.conname;


\echo ''
\echo '============================================================'
\echo '6. LOOKUP TABLE VALUES USED BY QUESTIONNAIRES'
\echo '============================================================'

select
  'categories' as lookup_table,
  sort_order,
  name,
  slug,
  is_active
from public.categories

union all

select
  'exhibitor_categories' as lookup_table,
  sort_order,
  name,
  slug,
  is_active
from public.exhibitor_categories

order by
  lookup_table,
  sort_order,
  slug;