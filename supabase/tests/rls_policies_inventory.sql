\pset pager off

select
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'profiles',
    'user_roles',
    'reviews',
    'visitor_review_details',
    'exhibitor_private_details',
    'favorites',
    'media',
    'review_reports',
    'media_reports'
  )
order by
  tablename,
  policyname;