-- ComicsAdvisor table grant hardening.
-- RLS controls which rows are accessible.
-- These grants control which operations each API role may attempt.

-- ============================================================
-- 1. REMOVE SUPABASE DEFAULT TABLE PRIVILEGES
-- ============================================================

revoke all privileges
on all tables in schema public
from anon, authenticated;


-- ============================================================
-- 2. PUBLIC CATALOG READS
-- ============================================================

grant select on table
  public.categories,
  public.exhibitor_categories,
  public.organizers,
  public.fairs,
  public.fair_categories,
  public.fair_editions,
  public.cosplay_contests,
  public.cosplay_benefits
to anon, authenticated;


-- ============================================================
-- 3. PUBLIC REVIEW AND MEDIA READS
-- ============================================================

grant select on table
  public.reviews,
  public.visitor_review_details,
  public.visitor_review_areas,
  public.exhibitor_review_details,
  public.cosplay_review_details,
  public.cosplay_review_activities,
  public.cosplay_review_benefits_used,
  public.media
to anon, authenticated;


-- ============================================================
-- 4. AUTHENTICATED CATALOG MANAGEMENT
-- ============================================================
-- RLS limits these operations to administrators.

grant insert, update, delete on table
  public.categories,
  public.exhibitor_categories,
  public.organizers,
  public.fairs,
  public.fair_categories,
  public.fair_editions,
  public.cosplay_contests,
  public.cosplay_benefits
to authenticated;


-- ============================================================
-- 5. PROFILES AND ROLES
-- ============================================================

grant select, insert, update on table
  public.profiles
to authenticated;

grant select, insert, update, delete on table
  public.user_roles
to authenticated;


-- ============================================================
-- 6. REVIEWS
-- ============================================================

grant select, insert, update on table
  public.reviews
to authenticated;


-- ============================================================
-- 7. VISITOR QUESTIONNAIRE
-- ============================================================

grant select, insert, update, delete on table
  public.visitor_review_details,
  public.visitor_review_areas
to authenticated;


-- ============================================================
-- 8. EXHIBITOR QUESTIONNAIRE
-- ============================================================

grant select, insert, update, delete on table
  public.exhibitor_review_details,
  public.exhibitor_private_details,
  public.exhibitor_review_return_factors
to authenticated;


-- ============================================================
-- 9. COSPLAY QUESTIONNAIRE
-- ============================================================

grant select, insert, update, delete on table
  public.cosplay_review_details,
  public.cosplay_review_activities,
  public.cosplay_review_benefits_used
to authenticated;


-- ============================================================
-- 10. FAVORITES
-- ============================================================

grant select, insert, update, delete on table
  public.favorites
to authenticated;


-- ============================================================
-- 11. MEDIA
-- ============================================================
-- No DELETE grant because the current RLS policies only define
-- public reads, authenticated inserts and owner updates.

grant insert, update on table
  public.media
to authenticated;


-- ============================================================
-- 12. REPORTS
-- ============================================================
-- Report authors can insert and authorized users can read.
-- Staff can update report status through the existing policies.

grant select, insert, update on table
  public.review_reports,
  public.media_reports
to authenticated;


-- ============================================================
-- 13. PREVENT FUTURE TABLES FROM RECEIVING BROAD PRIVILEGES
-- ============================================================
-- This applies to objects subsequently created by the role
-- executing these migrations.

alter default privileges in schema public
revoke all privileges on tables
from anon, authenticated;

alter default privileges in schema public
revoke all privileges on sequences
from anon, authenticated;

-- ============================================================
-- 14. REMOVE DEFAULT EXECUTE ACCESS FROM ALL PUBLIC FUNCTIONS
-- ============================================================
-- PostgreSQL grants EXECUTE on new functions to PUBLIC by
-- default. Supabase may also grant EXECUTE directly to anon,
-- authenticated and service_role.
--
-- Trigger functions are invoked by PostgreSQL triggers and do
-- not need to be directly executable through the API.

revoke execute
on all functions in schema public
from public, anon, authenticated, service_role;


-- ============================================================
-- 15. RLS HELPER FUNCTION ALLOWLIST
-- ============================================================
-- is_staff() is also used by policies available to anon.
-- Anonymous callers always receive false because auth.uid()
-- is null, but the function still needs EXECUTE permission for
-- the policy expression to be evaluated.

grant execute on function public.is_staff()
to anon, authenticated;

grant execute on function public.is_admin()
to authenticated;

grant execute on function public.is_verified_exhibitor()
to authenticated;


-- ============================================================
-- 16. APPLICATION RPC ALLOWLIST
-- ============================================================
-- Raw exhibitor responses remain private. This RPC returns only
-- aggregated values after checking the caller's verified role.

grant execute
on function public.get_exhibitor_economic_summary(uuid)
to authenticated;


-- ============================================================
-- 17. HARDEN SECURITY DEFINER SEARCH PATHS
-- ============================================================
-- All referenced objects inside these functions are already
-- schema-qualified, so an empty search_path is appropriate.

alter function public.is_staff()
set search_path = '';

alter function public.is_admin()
set search_path = '';

alter function public.is_verified_exhibitor()
set search_path = '';

alter function public.get_exhibitor_economic_summary(uuid)
set search_path = '';


-- ============================================================
-- 18. PREVENT BROAD EXECUTE GRANTS ON FUTURE FUNCTIONS
-- ============================================================
-- This applies to functions subsequently created by the role
-- executing the migrations, currently postgres.

alter default privileges
for role postgres
in schema public
revoke execute on functions
from public, anon, authenticated, service_role;