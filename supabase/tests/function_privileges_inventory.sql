\pset pager off

\echo ''
\echo '============================================================'
\echo '1. PUBLIC FUNCTIONS'
\echo '============================================================'

select
  p.oid::regprocedure as function_signature,
  pg_get_userbyid(p.proowner) as owner,
  l.lanname as language,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  p.proacl as explicit_acl
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
join pg_language l
  on l.oid = p.prolang
where n.nspname = 'public'
  and p.prokind = 'f'
order by p.oid::regprocedure::text;


\echo ''
\echo '============================================================'
\echo '2. EFFECTIVE EXECUTE PRIVILEGES'
\echo '============================================================'

select
  p.oid::regprocedure as function_signature,
  p.prosecdef as security_definer,
  has_function_privilege('anon', p.oid, 'EXECUTE')
    as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')
    as authenticated_can_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE')
    as service_role_can_execute
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
order by p.oid::regprocedure::text;


\echo ''
\echo '============================================================'
\echo '3. SECURITY DEFINER FUNCTIONS'
\echo '============================================================'

select
  p.oid::regprocedure as function_signature,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig as function_settings,
  has_function_privilege('anon', p.oid, 'EXECUTE')
    as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')
    as authenticated_can_execute
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and p.prosecdef
order by p.oid::regprocedure::text;