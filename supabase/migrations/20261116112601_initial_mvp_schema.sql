-- Comicsadvisor MVP - Supabase/PostgreSQL schema v1
-- Includes core entities, revised questionnaires, media, moderation, and RLS.
-- Run in a new Supabase project after review. Storage bucket policies are intentionally separate.

create extension if not exists pgcrypto;

-- ENUMS
create type public.account_status as enum ('active','limited','suspended','pending_deletion','deleted');
create type public.preferred_view as enum ('visitor','exhibitor','cosplayer','mixed');
create type public.user_role as enum ('visitor','exhibitor','cosplayer','moderator','admin');
create type public.verification_status as enum ('self_declared','pending','verified','rejected','revoked');
create type public.fair_status as enum ('draft','active','inactive','discontinued','archived');
create type public.edition_status as enum ('draft','announced','applications_open','applications_closed','ongoing','completed','postponed','cancelled','archived');
create type public.reviewer_role as enum ('visitor','exhibitor','cosplayer');
create type public.publication_status as enum ('draft','pending_review','published','hidden','rejected','deleted_by_author');
create type public.moderation_status as enum ('not_reviewed','pending','approved','flagged','hidden','rejected');
create type public.return_answer as enum ('yes','no','depends','unsure');
create type public.visit_duration as enum ('under_two_hours','half_day','full_day','multiple_days');
create type public.visit_company_type as enum ('alone','friends','partner','family_with_children','family_without_children','group_or_association','prefer_not_to_say');
create type public.fair_area_type as enum ('commercial_stands','artist_alley','cosplay','cosplay_contest','guests','comics_manga','card_games','board_games','video_games','workshops','stage','collectibles','food','accessibility','other');
create type public.attendance_days as enum ('one','some','all');
create type public.stand_size_range as enum ('up_to_4_sqm','sqm_5_9','sqm_10_18','sqm_19_36','over_36_sqm','unknown','prefer_not_to_say');
create type public.staff_size_range as enum ('one','two','three_to_five','more_than_five','prefer_not_to_say');
create type public.travel_origin as enum ('same_city_area','same_province','same_region','other_region','international','prefer_not_to_say');
create type public.booth_cost_range as enum ('free','under_100','from_100_to_249','from_250_to_499','from_500_to_999','from_1000_to_2499','from_2500_up','prefer_not_to_say');
create type public.expense_range as enum ('under_250','from_250_to_499','from_500_to_999','from_1000_to_2499','from_2500_to_4999','from_5000_up','prefer_not_to_say');
create type public.economic_outcome as enum ('strong_loss','slight_loss','break_even','slight_profit','good_profit','excellent_result','unknown_yet','prefer_not_to_say');
create type public.expectation_outcome as enum ('far_below','below','as_expected','above','far_above','prefer_not_to_say');
create type public.exhibitor_return_factor as enum ('booth_cost','stand_position','dates','attendance','target_audience','organization','distance_travel','other');
create type public.cosplay_participation_type as enum ('contest_spectator','cosplayer_not_competing','individual_contestant','group_contestant');
create type public.prize_match_answer as enum ('fully','partly','no','not_described','not_applicable');
create type public.prize_delivery_status as enum ('during_event','later','not_yet','not_applicable');
create type public.benefits_awareness as enum ('used','not_used','unaware','not_available');
create type public.cosplay_benefit_type as enum ('discounted_ticket','free_entry','costume_discount','priority_access','free_cloakroom','changing_room','prop_storage','photo_area','other');
create type public.media_category as enum ('atmosphere','stands','exhibitors','spaces','crowd','activities','cosplay','cosplay_contest','stage','food','services','accessibility','group','props','other');
create type public.report_reason as enum ('offensive_language','personal_data','suspected_fake_review','conflict_of_interest','spam','irrelevant_content','unsupported_serious_claim','copyright_concern','other');
create type public.report_status as enum ('open','under_review','resolved','dismissed');

-- HELPERS
create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- IDENTITIES
create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  home_region text,
  home_province text,
  onboarding_completed boolean not null default false,
  account_status public.account_status not null default 'active',
  preferred_view public.preferred_view not null default 'mixed',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role public.user_role not null,
  verification_status public.verification_status not null default 'self_declared',
  verified_at timestamptz,
  verified_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_id, role)
);

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles ur
    join public.profiles p on p.id = ur.profile_id
    where p.auth_user_id = (select auth.uid())
      and ur.role in ('moderator','admin')
      and ur.verification_status = 'verified'
  );
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles ur
    join public.profiles p on p.id = ur.profile_id
    where p.auth_user_id = (select auth.uid())
      and ur.role = 'admin' and ur.verification_status = 'verified'
  );
$$;

create or replace function public.is_verified_exhibitor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles ur
    join public.profiles p on p.id = ur.profile_id
    where p.auth_user_id = (select auth.uid())
      and ur.role = 'exhibitor' and ur.verification_status = 'verified'
  );
$$;


-- CATALOG
create table public.organizers (
  id uuid primary key default gen_random_uuid(), name text not null, slug text not null unique,
  description text, website_url text, email_public text, instagram_url text, facebook_url text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);

create table public.fairs (
  id uuid primary key default gen_random_uuid(), organizer_id uuid references public.organizers(id),
  name text not null, slug text not null unique, short_description text, description text,
  main_city text, main_province text, main_region text, default_venue_name text,
  website_url text, instagram_url text, facebook_url text,
  status public.fair_status not null default 'draft', created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);

create table public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, slug text not null unique,
  description text, icon_name text, is_active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.fair_categories (
  fair_id uuid not null references public.fairs(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  is_primary boolean not null default false, created_at timestamptz not null default now(),
  primary key(fair_id, category_id)
);

create table public.fair_editions (
  id uuid primary key default gen_random_uuid(), fair_id uuid not null references public.fairs(id) on delete cascade,
  name text not null, slug text not null, edition_number integer,
  start_date date not null, end_date date not null, status public.edition_status not null default 'draft', description text,
  venue_name text, address_line text, postal_code text, city text not null, province text, region text,
  country_code char(2) not null default 'IT', latitude numeric(9,6), longitude numeric(9,6),
  official_url text, ticket_url text, exhibitor_application_url text,
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique(fair_id, slug), check(end_date >= start_date)
);

create table public.exhibitor_categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, slug text not null unique,
  is_active boolean not null default true, sort_order integer not null default 0
);

-- COSPLAY OFFICIAL DATA
create table public.cosplay_contests (
  id uuid primary key default gen_random_uuid(), edition_id uuid not null references public.fair_editions(id) on delete cascade,
  name text not null, starts_at timestamptz, ends_at timestamptz, location_notes text,
  registration_url text, rules_url text, prizes_available boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table public.cosplay_benefits (
  id uuid primary key default gen_random_uuid(), edition_id uuid not null references public.fair_editions(id) on delete cascade,
  benefit_type public.cosplay_benefit_type not null, title text not null, description text,
  conditions text, source_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- REVIEWS: COMMON
create table public.reviews (
  id uuid primary key default gen_random_uuid(), edition_id uuid not null references public.fair_editions(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  reviewer_role public.reviewer_role not null, review_title text check (char_length(review_title) <= 80),
  overall_rating smallint not null check (overall_rating between 1 and 5),
  would_return public.return_answer, would_recommend public.return_answer,
  positive_notes text check (char_length(positive_notes) <= 1000),
  improvement_notes text check (char_length(improvement_notes) <= 1000),
  public_comment text check (char_length(public_comment) <= 2000),
  attendance_verified boolean not null default false,
  publication_status public.publication_status not null default 'draft',
  moderation_status public.moderation_status not null default 'not_reviewed',
  published_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique(author_id, edition_id, reviewer_role)
);

-- VISITOR QUESTIONNAIRE
create table public.visitor_review_details (
  review_id uuid primary key references public.reviews(id) on delete cascade,
  visit_duration public.visit_duration not null, first_visit boolean not null,
  attendance_date date, attended_multiple_days boolean not null default false,
  visit_company_type public.visit_company_type,
  organization_rating smallint not null check (organization_rating between 1 and 5),
  exhibitor_variety_rating smallint not null check (exhibitor_variety_rating between 1 and 5),
  stand_quality_rating smallint not null check (stand_quality_rating between 1 and 5),
  spaces_crowding_rating smallint not null check (spaces_crowding_rating between 1 and 5),
  services_cleanliness_rating smallint not null check (services_cleanliness_rating between 1 and 5),
  value_for_money_rating smallint not null check (value_for_money_rating between 1 and 5),
  queue_experienced boolean, queue_management_rating smallint check (queue_management_rating between 1 and 5),
  purchased_something boolean, product_variety_rating smallint check (product_variety_rating between 1 and 5),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (queue_experienced is true or queue_management_rating is null),
  check (purchased_something is true or product_variety_rating is null)
);
create table public.visitor_review_areas (
  review_id uuid not null references public.reviews(id) on delete cascade,
  area_type public.fair_area_type not null, area_rating smallint check (area_rating between 1 and 5),
  created_at timestamptz not null default now(), primary key(review_id, area_type)
);

-- EXHIBITOR QUESTIONNAIRE: PUBLIC
create table public.exhibitor_review_details (
  review_id uuid primary key references public.reviews(id) on delete cascade,
  first_participation boolean not null, attendance_days public.attendance_days not null,
  exhibitor_category_id uuid not null references public.exhibitor_categories(id),
  stand_size_range public.stand_size_range, staff_size_range public.staff_size_range, travel_origin public.travel_origin,
  handled_application boolean, used_exhibitor_passes boolean, used_exhibitor_parking boolean, handled_setup_teardown boolean,
  pre_event_communication_rating smallint not null check (pre_event_communication_rating between 1 and 5),
  organization_rating smallint not null check (organization_rating between 1 and 5),
  staff_support_rating smallint not null check (staff_support_rating between 1 and 5),
  logistics_rating smallint not null check (logistics_rating between 1 and 5),
  exhibitor_services_rating smallint not null check (exhibitor_services_rating between 1 and 5),
  application_clarity_rating smallint check (application_clarity_rating between 1 and 5),
  pass_management_rating smallint check (pass_management_rating between 1 and 5),
  parking_rating smallint check (parking_rating between 1 and 5),
  setup_teardown_rating smallint check (setup_teardown_rating between 1 and 5),
  attendance_rating smallint not null check (attendance_rating between 1 and 5),
  audience_fit_rating smallint not null check (audience_fit_rating between 1 and 5),
  space_quality_rating smallint not null check (space_quality_rating between 1 and 5),
  stand_position_rating smallint check (stand_position_rating between 1 and 5),
  security_rating smallint check (security_rating between 1 and 5),
  lighting_rating smallint check (lighting_rating between 1 and 5),
  connectivity_rating smallint check (connectivity_rating between 1 and 5),
  comfort_rating smallint check (comfort_rating between 1 and 5),
  event_promotion_rating smallint check (event_promotion_rating between 1 and 5),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (handled_application is true or application_clarity_rating is null),
  check (used_exhibitor_passes is true or pass_management_rating is null),
  check (used_exhibitor_parking is true or parking_rating is null),
  check (handled_setup_teardown is true or setup_teardown_rating is null)
);

-- EXHIBITOR QUESTIONNAIRE: PRIVATE
create table public.exhibitor_private_details (
  review_id uuid primary key references public.reviews(id) on delete cascade,
  booth_cost_range public.booth_cost_range, expense_range public.expense_range,
  economic_outcome public.economic_outcome, results_vs_costs_rating smallint check (results_vs_costs_rating between 1 and 5),
  expectation_outcome public.expectation_outcome,
  private_exhibitor_notes text check (char_length(private_exhibitor_notes) <= 2000),
  consent_for_aggregation boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.exhibitor_review_return_factors (
  review_id uuid not null references public.reviews(id) on delete cascade,
  factor public.exhibitor_return_factor not null, other_text text,
  primary key(review_id, factor),
  check(factor = 'other' or other_text is null)
);

-- COSPLAY QUESTIONNAIRE
create table public.cosplay_review_details (
  review_id uuid primary key references public.reviews(id) on delete cascade,
  primary_participation_type public.cosplay_participation_type not null,
  contest_id uuid references public.cosplay_contests(id),
  cosplay_experience_rating smallint not null check (cosplay_experience_rating between 1 and 5),
  area_organization_rating smallint not null check (area_organization_rating between 1 and 5),
  spaces_rating smallint not null check (spaces_rating between 1 and 5),
  cosplayer_treatment_rating smallint not null check (cosplayer_treatment_rating between 1 and 5),
  prop_safety_rating smallint not null check (prop_safety_rating between 1 and 5),
  changing_rooms_used boolean, changing_rooms_rating smallint check (changing_rooms_rating between 1 and 5),
  cloakroom_used boolean, cloakroom_rating smallint check (cloakroom_rating between 1 and 5),
  prop_storage_used boolean, prop_storage_rating smallint check (prop_storage_rating between 1 and 5),
  photo_area_used boolean, photo_area_rating smallint check (photo_area_rating between 1 and 5),
  watched_contest boolean not null default false,
  contest_quality_rating smallint check (contest_quality_rating between 1 and 5),
  stage_visibility_rating smallint check (stage_visibility_rating between 1 and 5),
  schedule_management_rating smallint check (schedule_management_rating between 1 and 5),
  audio_quality_rating smallint check (audio_quality_rating between 1 and 5),
  entertainment_rating smallint check (entertainment_rating between 1 and 5),
  program_respect_rating smallint check (program_respect_rating between 1 and 5),
  performance_variety_rating smallint check (performance_variety_rating between 1 and 5),
  rules_clarity_rating smallint check (rules_clarity_rating between 1 and 5),
  registration_rating smallint check (registration_rating between 1 and 5),
  contest_communication_rating smallint check (contest_communication_rating between 1 and 5),
  backstage_rating smallint check (backstage_rating between 1 and 5),
  staff_support_rating smallint check (staff_support_rating between 1 and 5),
  participant_treatment_rating smallint check (participant_treatment_rating between 1 and 5),
  contest_experience_rating smallint check (contest_experience_rating between 1 and 5),
  criteria_clarity_rating smallint check (criteria_clarity_rating between 1 and 5),
  awards_organization_rating smallint check (awards_organization_rating between 1 and 5),
  prize_received boolean, prize_matches_announcement public.prize_match_answer,
  prize_delivery_status public.prize_delivery_status, prize_delivery_notes text,
  benefits_awareness public.benefits_awareness,
  benefits_usefulness_rating smallint check (benefits_usefulness_rating between 1 and 5),
  would_join_contest_again public.return_answer,
  cosplayer_advice text check (char_length(cosplayer_advice) <= 1000),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (changing_rooms_used is true or changing_rooms_rating is null),
  check (cloakroom_used is true or cloakroom_rating is null),
  check (prop_storage_used is true or prop_storage_rating is null),
  check (photo_area_used is true or photo_area_rating is null),
  check (watched_contest is true or (contest_quality_rating is null and stage_visibility_rating is null and schedule_management_rating is null)),
  check (benefits_awareness = 'used' or benefits_usefulness_rating is null)
);
create table public.cosplay_review_activities (
  review_id uuid not null references public.reviews(id) on delete cascade,
  activity public.cosplay_participation_type not null, primary key(review_id, activity)
);
create table public.cosplay_review_benefits_used (
  review_id uuid not null references public.reviews(id) on delete cascade,
  benefit_type public.cosplay_benefit_type not null, primary key(review_id, benefit_type)
);

-- FAVORITES, MEDIA, REPORTS
create table public.favorites (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  fair_id uuid not null references public.fairs(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(profile_id, fair_id)
);
create table public.media (
  id uuid primary key default gen_random_uuid(), uploader_id uuid not null references public.profiles(id) on delete cascade,
  edition_id uuid not null references public.fair_editions(id) on delete cascade,
  review_id uuid references public.reviews(id) on delete set null, contest_id uuid references public.cosplay_contests(id) on delete set null,
  category public.media_category not null, storage_path text not null unique, thumbnail_storage_path text,
  width integer, height integer, file_size_bytes bigint, mime_type text not null,
  caption text check (char_length(caption) <= 500), alt_text text check (char_length(alt_text) <= 300),
  is_cover boolean not null default false, show_in_public_gallery boolean not null default true,
  rights_confirmed boolean not null default false,
  publication_status public.publication_status not null default 'pending_review',
  moderation_status public.moderation_status not null default 'pending',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check(file_size_bytes is null or file_size_bytes > 0), check(width is null or width > 0), check(height is null or height > 0)
);
create table public.review_reports (
  id uuid primary key default gen_random_uuid(), review_id uuid not null references public.reviews(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade, reason public.report_reason not null,
  notes text, status public.report_status not null default 'open', reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz, resolution text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(review_id, reporter_id)
);
create table public.media_reports (
  id uuid primary key default gen_random_uuid(), media_id uuid not null references public.media(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade, reason public.report_reason not null,
  notes text, status public.report_status not null default 'open', reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz, resolution text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(media_id, reporter_id)
);

-- INDEXES
create index idx_editions_fair_start on public.fair_editions(fair_id, start_date desc);
create index idx_reviews_edition_role_status on public.reviews(edition_id, reviewer_role, publication_status);
create index idx_reviews_author on public.reviews(author_id, created_at desc);
create index idx_media_edition_public on public.media(edition_id, publication_status, created_at desc);
create index idx_user_roles_profile_role_status on public.user_roles(profile_id, role, verification_status);
create index idx_reports_review_status on public.review_reports(status, created_at);
create index idx_reports_media_status on public.media_reports(status, created_at);

-- UPDATED_AT TRIGGERS
DO $$ declare t text; begin
  foreach t in array array['profiles','user_roles','organizers','fairs','categories','fair_editions','cosplay_contests','cosplay_benefits','reviews','visitor_review_details','exhibitor_review_details','exhibitor_private_details','cosplay_review_details','media','review_reports','media_reports']
  loop execute format('create trigger trg_%I_updated before update on public.%I for each row execute function public.set_updated_at()', t, t); end loop;
end $$;

-- BASIC ROLE VALIDATION TRIGGER
create or replace function public.validate_review_detail_role() returns trigger language plpgsql set search_path=public as $$
declare expected public.reviewer_role; actual public.reviewer_role;
begin
  expected := case TG_TABLE_NAME
    when 'visitor_review_details' then 'visitor'::reviewer_role
    when 'exhibitor_review_details' then 'exhibitor'::reviewer_role
    when 'exhibitor_private_details' then 'exhibitor'::reviewer_role
    when 'cosplay_review_details' then 'cosplayer'::reviewer_role end;
  select reviewer_role into actual from public.reviews where id = new.review_id;
  if actual is distinct from expected then raise exception 'Questionnaire does not match review role'; end if;
  return new;
end $$;
create trigger validate_visitor_role before insert or update on public.visitor_review_details for each row execute function public.validate_review_detail_role();
create trigger validate_exhibitor_role before insert or update on public.exhibitor_review_details for each row execute function public.validate_review_detail_role();
create trigger validate_exhibitor_private_role before insert or update on public.exhibitor_private_details for each row execute function public.validate_review_detail_role();
create trigger validate_cosplay_role before insert or update on public.cosplay_review_details for each row execute function public.validate_review_detail_role();

-- RLS
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.organizers enable row level security;
alter table public.fairs enable row level security;
alter table public.categories enable row level security;
alter table public.fair_categories enable row level security;
alter table public.fair_editions enable row level security;
alter table public.exhibitor_categories enable row level security;
alter table public.cosplay_contests enable row level security;
alter table public.cosplay_benefits enable row level security;
alter table public.reviews enable row level security;
alter table public.visitor_review_details enable row level security;
alter table public.visitor_review_areas enable row level security;
alter table public.exhibitor_review_details enable row level security;
alter table public.exhibitor_private_details enable row level security;
alter table public.exhibitor_review_return_factors enable row level security;
alter table public.cosplay_review_details enable row level security;
alter table public.cosplay_review_activities enable row level security;
alter table public.cosplay_review_benefits_used enable row level security;
alter table public.favorites enable row level security;
alter table public.media enable row level security;
alter table public.review_reports enable row level security;
alter table public.media_reports enable row level security;

-- Public catalog reads
create policy catalog_organizers_read on public.organizers for select to anon, authenticated using (deleted_at is null);
create policy catalog_fairs_read on public.fairs for select to anon, authenticated using (deleted_at is null and status <> 'draft');
create policy catalog_categories_read on public.categories for select to anon, authenticated using (is_active);
create policy catalog_fair_categories_read on public.fair_categories for select to anon, authenticated using (true);
create policy catalog_editions_read on public.fair_editions for select to anon, authenticated using (deleted_at is null and status <> 'draft');
create policy exhibitor_categories_read on public.exhibitor_categories for select to anon, authenticated using (is_active);
create policy cosplay_contests_read on public.cosplay_contests for select to anon, authenticated using (deleted_at is null);
create policy cosplay_benefits_read on public.cosplay_benefits for select to anon, authenticated using (true);

-- Admin catalog writes
create policy catalog_organizers_admin on public.organizers for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy catalog_fairs_admin on public.fairs for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy catalog_categories_admin on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy catalog_fair_categories_admin on public.fair_categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy catalog_editions_admin on public.fair_editions for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy exhibitor_categories_admin on public.exhibitor_categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy cosplay_contests_admin on public.cosplay_contests for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy cosplay_benefits_admin on public.cosplay_benefits for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Profiles and roles
create policy profiles_self_read on public.profiles for select to authenticated using (auth_user_id = (select auth.uid()) or public.is_staff());
create policy profiles_self_insert on public.profiles for insert to authenticated with check (auth_user_id = (select auth.uid()));
create policy profiles_self_update on public.profiles for update to authenticated using (auth_user_id = (select auth.uid())) with check (auth_user_id = (select auth.uid()));
create policy roles_self_read on public.user_roles for select to authenticated using (profile_id = (select id from public.profiles where auth_user_id = (select auth.uid())) or public.is_staff());
create policy roles_self_insert_nonstaff on public.user_roles for insert to authenticated with check (
  profile_id = (select id from public.profiles where auth_user_id = (select auth.uid())) and role in ('visitor','exhibitor','cosplayer')
);
create policy roles_staff_manage on public.user_roles for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Reviews public/owner/staff
create policy reviews_read on public.reviews for select to anon, authenticated using (
  (publication_status='published' and moderation_status in ('approved','not_reviewed','flagged'))
  or author_id = (select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff()
);
create policy reviews_insert on public.reviews for insert to authenticated with check (
  author_id = (select id from public.profiles where auth_user_id=(select auth.uid()))
);
create policy reviews_update_owner on public.reviews for update to authenticated using (
  author_id = (select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff()
) with check (author_id = (select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff());

-- Public questionnaire details, gated by parent review visibility
create policy visitor_details_read on public.visitor_review_details for select to anon, authenticated using (exists(select 1 from public.reviews r where r.id=review_id));
create policy visitor_areas_read on public.visitor_review_areas for select to anon, authenticated using (exists(select 1 from public.reviews r where r.id=review_id));
create policy exhibitor_details_read on public.exhibitor_review_details for select to anon, authenticated using (exists(select 1 from public.reviews r where r.id=review_id));
create policy cosplay_details_read on public.cosplay_review_details for select to anon, authenticated using (exists(select 1 from public.reviews r where r.id=review_id));
create policy cosplay_activities_read on public.cosplay_review_activities for select to anon, authenticated using (exists(select 1 from public.reviews r where r.id=review_id));
create policy cosplay_benefits_used_read on public.cosplay_review_benefits_used for select to anon, authenticated using (exists(select 1 from public.reviews r where r.id=review_id));

-- Owner writes questionnaire details
create policy visitor_details_owner on public.visitor_review_details for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));
create policy visitor_areas_owner on public.visitor_review_areas for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));
create policy exhibitor_details_owner on public.exhibitor_review_details for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));
create policy cosplay_details_owner on public.cosplay_review_details for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));
create policy cosplay_activities_owner on public.cosplay_review_activities for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));
create policy cosplay_benefits_owner on public.cosplay_review_benefits_used for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));

-- Private exhibitor data: owner or staff only. Other exhibitors must use an aggregate RPC/view, not raw rows.
create policy exhibitor_private_owner_staff_read on public.exhibitor_private_details for select to authenticated using (
  exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())) or public.is_staff()
);
create policy exhibitor_private_owner_write on public.exhibitor_private_details for all to authenticated using (
  exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))
) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));
create policy exhibitor_factors_owner on public.exhibitor_review_return_factors for all to authenticated using (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid()))) with check (exists(select 1 from public.reviews r join public.profiles p on p.id=r.author_id where r.id=review_id and p.auth_user_id=(select auth.uid())));

-- Favorites
create policy favorites_owner on public.favorites for all to authenticated using (profile_id=(select id from public.profiles where auth_user_id=(select auth.uid()))) with check (profile_id=(select id from public.profiles where auth_user_id=(select auth.uid())));

-- Media metadata. Storage object policies must separately enforce upload/read permissions.
create policy media_read on public.media for select to anon, authenticated using ((publication_status='published' and moderation_status in ('approved','not_reviewed','flagged') and show_in_public_gallery) or uploader_id=(select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff());
create policy media_insert on public.media for insert to authenticated with check (uploader_id=(select id from public.profiles where auth_user_id=(select auth.uid())) and rights_confirmed);
create policy media_update_owner on public.media for update to authenticated using (uploader_id=(select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff()) with check (uploader_id=(select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff());

-- Reports
create policy review_reports_owner_insert on public.review_reports for insert to authenticated with check (reporter_id=(select id from public.profiles where auth_user_id=(select auth.uid())));
create policy review_reports_owner_staff_read on public.review_reports for select to authenticated using (reporter_id=(select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff());
create policy review_reports_staff_update on public.review_reports for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy media_reports_owner_insert on public.media_reports for insert to authenticated with check (reporter_id=(select id from public.profiles where auth_user_id=(select auth.uid())));
create policy media_reports_owner_staff_read on public.media_reports for select to authenticated using (reporter_id=(select id from public.profiles where auth_user_id=(select auth.uid())) or public.is_staff());
create policy media_reports_staff_update on public.media_reports for update to authenticated using (public.is_staff()) with check (public.is_staff());

-- Safe aggregate function for verified exhibitors. Minimum sample = 5.
create or replace function public.get_exhibitor_economic_summary(p_edition_id uuid)
returns table(metric text, value text, response_count bigint)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_verified_exhibitor() and not public.is_staff() then raise exception 'Not authorized'; end if;
  if (select count(*) from public.exhibitor_private_details ep join public.reviews r on r.id=ep.review_id
      where r.edition_id=p_edition_id and r.publication_status='published' and ep.consent_for_aggregation) < 5 then
    return query select 'insufficient_data'::text, null::text, count(*)
      from public.exhibitor_private_details ep join public.reviews r on r.id=ep.review_id
      where r.edition_id=p_edition_id and r.publication_status='published' and ep.consent_for_aggregation;
    return;
  end if;
  return query
    select 'economic_outcome'::text, ep.economic_outcome::text, count(*)
    from public.exhibitor_private_details ep join public.reviews r on r.id=ep.review_id
    where r.edition_id=p_edition_id and r.publication_status='published' and ep.consent_for_aggregation and ep.economic_outcome is not null
    group by ep.economic_outcome
    union all
    select 'expense_range'::text, ep.expense_range::text, count(*)
    from public.exhibitor_private_details ep join public.reviews r on r.id=ep.review_id
    where r.edition_id=p_edition_id and r.publication_status='published' and ep.consent_for_aggregation and ep.expense_range is not null
    group by ep.expense_range
    union all
    select 'booth_cost_range'::text, ep.booth_cost_range::text, count(*)
    from public.exhibitor_private_details ep join public.reviews r on r.id=ep.review_id
    where r.edition_id=p_edition_id and r.publication_status='published' and ep.consent_for_aggregation and ep.booth_cost_range is not null
    group by ep.booth_cost_range;
end $$;
revoke all on function public.get_exhibitor_economic_summary(uuid) from public, anon;
grant execute on function public.get_exhibitor_economic_summary(uuid) to authenticated;

-- Explicit grants should be reviewed against the exact Data API surface before production.
grant select on public.organizers, public.fairs, public.categories, public.fair_categories, public.fair_editions,
  public.exhibitor_categories, public.cosplay_contests, public.cosplay_benefits,
  public.reviews, public.visitor_review_details, public.visitor_review_areas,
  public.exhibitor_review_details, public.cosplay_review_details,
  public.cosplay_review_activities, public.cosplay_review_benefits_used, public.media to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
