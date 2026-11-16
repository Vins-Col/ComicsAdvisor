begin;

do $$
declare
  v_profile_id uuid;
  v_fair_id uuid;
  v_past_edition_id uuid;
  v_future_edition_id uuid;
  v_other_edition_id uuid;
  v_visitor_review_id uuid;
  v_exhibitor_review_id uuid;
  v_cosplay_review_id uuid;
  v_wrong_contest_id uuid;
  v_category_id uuid;
begin
  -- ----------------------------------------------------------
  -- Test fixtures
  -- ----------------------------------------------------------

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'review-integrity-test@comicsadvisor.local',
    crypt('TestPassword123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Review Integrity Test"}'::jsonb,
    now(),
    now()
  );

  select id
  into strict v_profile_id
  from public.profiles
  where display_name = 'Review Integrity Test';

  insert into public.fairs (
    name,
    slug,
    status,
    created_by
  )
  values (
    'Review Integrity Test Fair',
    'review-integrity-test-fair',
    'active',
    v_profile_id
  )
  returning id into v_fair_id;

  insert into public.fair_editions (
    fair_id,
    name,
    slug,
    start_date,
    end_date,
    status,
    city,
    created_by
  )
  values
    (
      v_fair_id,
      'Past Edition',
      'past-edition',
      current_date - 10,
      current_date - 8,
      'completed',
      'Test City',
      v_profile_id
    ),
    (
      v_fair_id,
      'Future Edition',
      'future-edition',
      current_date + 10,
      current_date + 12,
      'announced',
      'Test City',
      v_profile_id
    ),
    (
      v_fair_id,
      'Other Past Edition',
      'other-past-edition',
      current_date - 20,
      current_date - 18,
      'completed',
      'Test City',
      v_profile_id
    );

  select id into strict v_past_edition_id
  from public.fair_editions
  where fair_id = v_fair_id and slug = 'past-edition';

  select id into strict v_future_edition_id
  from public.fair_editions
  where fair_id = v_fair_id and slug = 'future-edition';

  select id into strict v_other_edition_id
  from public.fair_editions
  where fair_id = v_fair_id and slug = 'other-past-edition';

  select id
  into strict v_category_id
  from public.exhibitor_categories
  where slug = 'altro';

  -- ----------------------------------------------------------
  -- Test 1: future edition must be rejected
  -- ----------------------------------------------------------

  begin
    insert into public.reviews (
      edition_id,
      author_id,
      reviewer_role,
      overall_rating
    )
    values (
      v_future_edition_id,
      v_profile_id,
      'visitor',
      4
    );

    raise exception 'TEST FAILED: future edition review was accepted';
  exception
    when check_violation then
      if sqlerrm <> 'Reviews can only be created after the fair edition has ended.' then
        raise;
      end if;

      raise notice 'PASS 1: future edition review rejected';
  end;

  -- ----------------------------------------------------------
  -- Create valid review headers
  -- ----------------------------------------------------------

  insert into public.reviews (
    edition_id,
    author_id,
    reviewer_role,
    overall_rating
  )
  values (
    v_past_edition_id,
    v_profile_id,
    'visitor',
    4
  )
  returning id into v_visitor_review_id;

  insert into public.reviews (
    edition_id,
    author_id,
    reviewer_role,
    overall_rating
  )
  values (
    v_past_edition_id,
    v_profile_id,
    'exhibitor',
    4
  )
  returning id into v_exhibitor_review_id;

  insert into public.reviews (
    edition_id,
    author_id,
    reviewer_role,
    overall_rating
  )
  values (
    v_past_edition_id,
    v_profile_id,
    'cosplayer',
    4
  )
  returning id into v_cosplay_review_id;

  -- ----------------------------------------------------------
  -- Test 2: visitor details on exhibitor review must fail
  -- ----------------------------------------------------------

  begin
    insert into public.visitor_review_details (
      review_id,
      visit_duration,
      first_visit,
      attendance_date,
      attended_multiple_days,
      organization_rating,
      exhibitor_variety_rating,
      stand_quality_rating,
      spaces_crowding_rating,
      services_cleanliness_rating,
      value_for_money_rating
    )
    values (
      v_exhibitor_review_id,
      'full_day',
      true,
      current_date - 9,
      false,
      4, 4, 4, 4, 4, 4
    );

    raise exception 'TEST FAILED: visitor details accepted an exhibitor review';
  exception
    when check_violation then
      if sqlerrm not like 'This questionnaire requires a visitor review%' then
        raise;
      end if;

      raise notice 'PASS 2: mismatched visitor questionnaire rejected';
  end;

  -- ----------------------------------------------------------
  -- Test 3: attendance date outside edition must fail
  -- ----------------------------------------------------------

  begin
    insert into public.visitor_review_details (
      review_id,
      visit_duration,
      first_visit,
      attendance_date,
      attended_multiple_days,
      organization_rating,
      exhibitor_variety_rating,
      stand_quality_rating,
      spaces_crowding_rating,
      services_cleanliness_rating,
      value_for_money_rating
    )
    values (
      v_visitor_review_id,
      'full_day',
      true,
      current_date - 30,
      false,
      4, 4, 4, 4, 4, 4
    );

    raise exception 'TEST FAILED: out-of-range attendance date was accepted';
  exception
    when check_violation then
      if sqlerrm not like 'The attendance date must be between%' then
        raise;
      end if;

      raise notice 'PASS 3: out-of-range attendance date rejected';
  end;

  -- Insert valid visitor details for later mutation tests.

  insert into public.visitor_review_details (
    review_id,
    visit_duration,
    first_visit,
    attendance_date,
    attended_multiple_days,
    organization_rating,
    exhibitor_variety_rating,
    stand_quality_rating,
    spaces_crowding_rating,
    services_cleanliness_rating,
    value_for_money_rating
  )
  values (
    v_visitor_review_id,
    'full_day',
    true,
    current_date - 9,
    false,
    4, 4, 4, 4, 4, 4
  );

  -- ----------------------------------------------------------
  -- Test 4: review role cannot change after details exist
  -- ----------------------------------------------------------

  begin
    update public.reviews
    set reviewer_role = 'exhibitor'
    where id = v_visitor_review_id;

    raise exception 'TEST FAILED: review role changed after details existed';
  exception
    when check_violation then
      if sqlerrm <> 'The review role cannot be changed after questionnaire details have been created.' then
        raise;
      end if;

      raise notice 'PASS 4: review role change rejected';
  end;

  -- ----------------------------------------------------------
  -- Test 5: review edition cannot change after details exist
  -- ----------------------------------------------------------

  begin
    update public.reviews
    set edition_id = v_other_edition_id
    where id = v_visitor_review_id;

    raise exception 'TEST FAILED: review edition changed after details existed';
  exception
    when check_violation then
      if sqlerrm <> 'The fair edition cannot be changed after questionnaire details have been created.' then
        raise;
      end if;

      raise notice 'PASS 5: review edition change rejected';
  end;

  -- ----------------------------------------------------------
  -- Test 6: exhibitor private details require exhibitor role
  -- ----------------------------------------------------------

  begin
    insert into public.exhibitor_private_details (
      review_id,
      economic_outcome,
      consent_for_aggregation
    )
    values (
      v_visitor_review_id,
      'break_even',
      true
    );

    raise exception 'TEST FAILED: exhibitor private data accepted a visitor review';
  exception
    when check_violation then
      if sqlerrm not like 'This questionnaire requires a exhibitor review%' then
        raise;
      end if;

      raise notice 'PASS 6: private exhibitor data rejected for visitor review';
  end;

  -- Add valid exhibitor details, proving the matching role succeeds.

  insert into public.exhibitor_review_details (
    review_id,
    first_participation,
    attendance_days,
    exhibitor_category_id,
    pre_event_communication_rating,
    organization_rating,
    staff_support_rating,
    logistics_rating,
    exhibitor_services_rating,
    attendance_rating,
    audience_fit_rating,
    space_quality_rating
  )
  values (
    v_exhibitor_review_id,
    true,
    'all',
    v_category_id,
    4, 4, 4, 4, 4, 4, 4, 4
  );

  -- ----------------------------------------------------------
  -- Test 7: cosplay contest must belong to review edition
  -- ----------------------------------------------------------

  insert into public.cosplay_contests (
    edition_id,
    name,
    prizes_available
  )
  values (
    v_other_edition_id,
    'Wrong Edition Contest',
    true
  )
  returning id into v_wrong_contest_id;

  begin
    insert into public.cosplay_review_details (
      review_id,
      primary_participation_type,
      contest_id,
      cosplay_experience_rating,
      area_organization_rating,
      spaces_rating,
      cosplayer_treatment_rating,
      prop_safety_rating
    )
    values (
      v_cosplay_review_id,
      'individual_contestant',
      v_wrong_contest_id,
      4, 4, 4, 4, 4
    );

    raise exception 'TEST FAILED: contest from another edition was accepted';
  exception
    when check_violation then
      if sqlerrm <> 'The selected cosplay contest does not belong to the review edition.' then
        raise;
      end if;

      raise notice 'PASS 7: contest from another edition rejected';
  end;

  raise notice 'ALL REVIEW INTEGRITY TESTS PASSED';
end;
$$ language plpgsql;

rollback;