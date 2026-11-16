-- ComicsAdvisor review integrity validations.
-- Prevents inconsistent review, questionnaire, edition and contest data.

-- ============================================================
-- 1. REVIEWS CAN ONLY BE CREATED FOR ENDED EDITIONS
-- ============================================================

create or replace function public.validate_review_edition_completed()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_end_date date;
  v_status public.edition_status;
begin
  select
    edition.end_date,
    edition.status
  into
    v_end_date,
    v_status
  from public.fair_editions as edition
  where edition.id = new.edition_id
    and edition.deleted_at is null;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The selected fair edition does not exist or is unavailable.';
  end if;

  if v_status in ('cancelled', 'postponed') then
    raise exception using
      errcode = '23514',
      message = 'Reviews cannot be created for a cancelled or postponed edition.';
  end if;

  if v_end_date >= current_date then
    raise exception using
      errcode = '23514',
      message = 'Reviews can only be created after the fair edition has ended.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_review_edition_completed_trigger
  on public.reviews;

create trigger validate_review_edition_completed_trigger
before insert or update of edition_id
on public.reviews
for each row
execute function public.validate_review_edition_completed();

-- Remove the legacy role-validation triggers created by the initial
-- schema. The generic parameterized triggers below replace them.

drop trigger if exists validate_visitor_role
  on public.visitor_review_details;

drop trigger if exists validate_exhibitor_role
  on public.exhibitor_review_details;

drop trigger if exists validate_exhibitor_private_role
  on public.exhibitor_private_details;

drop trigger if exists validate_cosplay_role
  on public.cosplay_review_details;

-- ============================================================
-- 2. GENERIC QUESTIONNAIRE ROLE VALIDATION
-- ============================================================

create or replace function public.validate_review_detail_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_actual_role public.reviewer_role;
  v_expected_role public.reviewer_role;
begin
  if tg_nargs <> 1 or tg_argv[0] is null then
    raise exception using
      errcode = '22023',
      message = 'The review role validation trigger requires exactly one role argument.';
  end if;
  v_expected_role := tg_argv[0]::public.reviewer_role;

  select review.reviewer_role
  into v_actual_role
  from public.reviews as review
  where review.id = new.review_id
    and review.deleted_at is null;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The referenced review does not exist or is unavailable.';
  end if;

  if v_actual_role <> v_expected_role then
    raise exception using
      errcode = '23514',
      message = format(
        'This questionnaire requires a %s review, but the referenced review has role %s.',
        v_expected_role,
        v_actual_role
      );
  end if;

  return new;
end;
$$;


-- Visitor details

drop trigger if exists validate_visitor_review_details_role_trigger
  on public.visitor_review_details;

create trigger validate_visitor_review_details_role_trigger
before insert or update of review_id
on public.visitor_review_details
for each row
execute function public.validate_review_detail_role('visitor');


drop trigger if exists validate_visitor_review_areas_role_trigger
  on public.visitor_review_areas;

create trigger validate_visitor_review_areas_role_trigger
before insert or update of review_id
on public.visitor_review_areas
for each row
execute function public.validate_review_detail_role('visitor');


-- Exhibitor details

drop trigger if exists validate_exhibitor_review_details_role_trigger
  on public.exhibitor_review_details;

create trigger validate_exhibitor_review_details_role_trigger
before insert or update of review_id
on public.exhibitor_review_details
for each row
execute function public.validate_review_detail_role('exhibitor');


drop trigger if exists validate_exhibitor_private_details_role_trigger
  on public.exhibitor_private_details;

create trigger validate_exhibitor_private_details_role_trigger
before insert or update of review_id
on public.exhibitor_private_details
for each row
execute function public.validate_review_detail_role('exhibitor');


drop trigger if exists validate_exhibitor_return_factors_role_trigger
  on public.exhibitor_review_return_factors;

create trigger validate_exhibitor_return_factors_role_trigger
before insert or update of review_id
on public.exhibitor_review_return_factors
for each row
execute function public.validate_review_detail_role('exhibitor');


-- Cosplay details

drop trigger if exists validate_cosplay_review_details_role_trigger
  on public.cosplay_review_details;

create trigger validate_cosplay_review_details_role_trigger
before insert or update of review_id
on public.cosplay_review_details
for each row
execute function public.validate_review_detail_role('cosplayer');


drop trigger if exists validate_cosplay_review_activities_role_trigger
  on public.cosplay_review_activities;

create trigger validate_cosplay_review_activities_role_trigger
before insert or update of review_id
on public.cosplay_review_activities
for each row
execute function public.validate_review_detail_role('cosplayer');


drop trigger if exists validate_cosplay_benefits_used_role_trigger
  on public.cosplay_review_benefits_used;

create trigger validate_cosplay_benefits_used_role_trigger
before insert or update of review_id
on public.cosplay_review_benefits_used
for each row
execute function public.validate_review_detail_role('cosplayer');


-- ============================================================
-- 3. PREVENT CHANGING A REVIEW ROLE AFTER DETAILS EXIST
-- ============================================================

create or replace function public.validate_review_role_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.reviewer_role = old.reviewer_role then
    return new;
  end if;

  if exists (
    select 1
    from public.visitor_review_details
    where review_id = old.id

    union all

    select 1
    from public.visitor_review_areas
    where review_id = old.id

    union all

    select 1
    from public.exhibitor_review_details
    where review_id = old.id

    union all

    select 1
    from public.exhibitor_private_details
    where review_id = old.id

    union all

    select 1
    from public.exhibitor_review_return_factors
    where review_id = old.id

    union all

    select 1
    from public.cosplay_review_details
    where review_id = old.id

    union all

    select 1
    from public.cosplay_review_activities
    where review_id = old.id

    union all

    select 1
    from public.cosplay_review_benefits_used
    where review_id = old.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'The review role cannot be changed after questionnaire details have been created.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_review_role_change_trigger
  on public.reviews;

create trigger validate_review_role_change_trigger
before update of reviewer_role
on public.reviews
for each row
execute function public.validate_review_role_change();


-- ============================================================
-- 4. VISITOR ATTENDANCE DATE MUST BELONG TO THE EDITION
-- ============================================================

create or replace function public.validate_visitor_attendance_date()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_start_date date;
  v_end_date date;
begin
  select
    edition.start_date,
    edition.end_date
  into
    v_start_date,
    v_end_date
  from public.reviews as review
  join public.fair_editions as edition
    on edition.id = review.edition_id
  where review.id = new.review_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The review or its fair edition could not be found.';
  end if;

  if new.attendance_date is not null
     and new.attendance_date not between v_start_date and v_end_date then
    raise exception using
      errcode = '23514',
      message = format(
        'The attendance date must be between %s and %s.',
        v_start_date,
        v_end_date
      );
  end if;

  if new.attended_multiple_days is true
     and v_start_date = v_end_date then
    raise exception using
      errcode = '23514',
      message = 'Multiple attendance days cannot be selected for a one-day edition.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_visitor_attendance_date_trigger
  on public.visitor_review_details;

create trigger validate_visitor_attendance_date_trigger
before insert or update of review_id, attendance_date, attended_multiple_days
on public.visitor_review_details
for each row
execute function public.validate_visitor_attendance_date();


-- ============================================================
-- 5. COSPLAY CONTEST MUST BELONG TO THE REVIEW EDITION
-- ============================================================

create or replace function public.validate_cosplay_contest_edition()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_review_edition_id uuid;
  v_contest_edition_id uuid;
begin
  if new.contest_id is null then
    return new;
  end if;

  select review.edition_id
  into v_review_edition_id
  from public.reviews as review
  where review.id = new.review_id
    and review.deleted_at is null;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The referenced review does not exist or is unavailable.';
  end if;

  select contest.edition_id
  into v_contest_edition_id
  from public.cosplay_contests as contest
  where contest.id = new.contest_id
    and contest.deleted_at is null;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The selected cosplay contest does not exist or is unavailable.';
  end if;

  if v_review_edition_id <> v_contest_edition_id then
    raise exception using
      errcode = '23514',
      message = 'The selected cosplay contest does not belong to the review edition.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_cosplay_contest_edition_trigger
  on public.cosplay_review_details;

create trigger validate_cosplay_contest_edition_trigger
before insert or update of review_id, contest_id
on public.cosplay_review_details
for each row
execute function public.validate_cosplay_contest_edition();


-- ============================================================
-- 6. PREVENT MOVING A REVIEW TO ANOTHER EDITION AFTER DETAILS
-- ============================================================

create or replace function public.validate_review_edition_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.edition_id = old.edition_id then
    return new;
  end if;

  if exists (
    select 1
    from public.visitor_review_details
    where review_id = old.id

    union all

    select 1
    from public.visitor_review_areas
    where review_id = old.id

    union all

    select 1
    from public.exhibitor_review_details
    where review_id = old.id

    union all

    select 1
    from public.exhibitor_private_details
    where review_id = old.id

    union all

    select 1
    from public.exhibitor_review_return_factors
    where review_id = old.id

    union all

    select 1
    from public.cosplay_review_details
    where review_id = old.id

    union all

    select 1
    from public.cosplay_review_activities
    where review_id = old.id

    union all

    select 1
    from public.cosplay_review_benefits_used
    where review_id = old.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'The fair edition cannot be changed after questionnaire details have been created.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_review_edition_change_trigger
  on public.reviews;

create trigger validate_review_edition_change_trigger
before update of edition_id
on public.reviews
for each row
execute function public.validate_review_edition_change();