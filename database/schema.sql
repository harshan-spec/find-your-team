-- Find your team uses isolated tables; existing marketplace data is untouched.
create schema if not exists team_private;
revoke all on schema team_private from public;
grant usage on schema team_private to anon, authenticated;
create table public.team_posts (
 id uuid primary key,
 title text not null check (length(btrim(title)) between 5 and 120),
 event_name text not null check (length(btrim(event_name)) between 2 and 120),
 type text not null check(type in ('Hackathon','Competition','Cultural','Sports','Project','Other')),
 description text not null check(length(btrim(description)) between 40 and 3000),
 skills text[] not null check(cardinality(skills) between 1 and 12 and length(array_to_string(skills,','))<=250),
 year text not null check(year in ('Any year','1st year','2nd year','3rd year','4th year','5th year','Postgraduate')),
 department text not null check(department in ('Any department','CSE','IT','ECE','EEE','Mechanical','Civil','Chemical','Biotechnology','AI & DS','Other')),
 gender text not null check(gender in ('Both / everyone','Girls','Boys')),
 mode text not null check(mode in ('On campus','Online','Hybrid')),
 location text not null check(length(btrim(location)) between 2 and 120),
 college text not null check(length(btrim(college)) between 2 and 120),
 seats integer not null check(seats between 1 and 100),
 deadline date not null,
 event_url text not null default '' check(event_url='' or (event_url ~ '^https?://[^[:space:]]+$' and length(event_url)<=500)),
 name text not null check(length(btrim(name)) between 2 and 120),
 email text not null check(length(email)<=200 and email ~ '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
 status text not null default 'open' check(status in ('open','closed','hidden')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.team_posts enable row level security;
revoke all on public.team_posts from anon,authenticated;
grant select on public.team_posts to anon,authenticated;
create policy "Read visible team opportunities" on public.team_posts for select to anon,authenticated using(status in ('open','closed'));
create index team_posts_created_idx on public.team_posts(created_at desc);
create index team_posts_open_deadline_idx on public.team_posts(deadline) where status='open';
create table team_private.post_keys(post_id uuid primary key references public.team_posts(id) on delete cascade,key_hash text not null);
create table team_private.reports(id uuid primary key default gen_random_uuid(),post_id uuid references public.team_posts(id) on delete set null,reason text not null check(length(btrim(reason)) between 10 and 2000),created_at timestamptz not null default now(),reviewed boolean not null default false);
create index team_reports_post_idx on team_private.reports(post_id);
create table team_private.rate_limits(bucket text primary key,started_at timestamptz not null default now(),hits integer not null default 1);
alter table team_private.post_keys enable row level security;
alter table team_private.reports enable row level security;
alter table team_private.rate_limits enable row level security;
revoke all on all tables in schema team_private from public,anon,authenticated;
create policy "No direct key access" on team_private.post_keys for all to anon,authenticated using(false) with check(false);
create policy "No direct moderation access" on team_private.reports for all to anon,authenticated using(false) with check(false);
create policy "No direct rate limit access" on team_private.rate_limits for all to anon,authenticated using(false) with check(false);

-- Only privileged capability-checked routines can mutate data. No service key in the browser.
create function team_private.rate_check(p_bucket text,p_limit integer) returns void language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into team_private.rate_limits(bucket) values(p_bucket)
 on conflict(bucket) do update set
 hits=case when team_private.rate_limits.started_at < now()-interval '1 hour' then 1 else team_private.rate_limits.hits+1 end,
 started_at=case when team_private.rate_limits.started_at < now()-interval '1 hour' then now() else team_private.rate_limits.started_at end
 returning hits into n;
 if n>p_limit then raise exception 'Too many requests. Please try again later.';end if;
end;$$;
revoke all on function team_private.rate_check(text,integer) from public,anon,authenticated;

create function team_private.write_post(p_id uuid,p_key text,p_data jsonb,p_action text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_hash text; v_ip text; v_deadline date;
begin
 if p_key is null or p_key !~ '^[a-f0-9]{64}$' then raise exception 'A valid private management key is required.';end if;
 if p_action not in ('create','edit','close','reopen','delete') or p_action is null then raise exception 'Unknown action.';end if;
 v_hash:=encode(sha256(convert_to(p_key,'UTF8')),'hex');
 v_ip:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-forwarded-for','unknown');
 if p_action='create' then
  perform team_private.rate_check('create:ip:'||md5(v_ip),40);
  perform team_private.rate_check('create:key:'||v_hash,10);
 else
  select key_hash into v_hash from team_private.post_keys where post_id=p_id;
  if v_hash is null or v_hash<>encode(sha256(convert_to(p_key,'UTF8')),'hex') then raise exception 'This management key cannot edit this post.';end if;
 end if;
 if p_action in ('create','edit') then
  v_deadline:=(p_data->>'deadline')::date;
  if v_deadline is null or v_deadline < (now() at time zone 'Asia/Kolkata')::date then raise exception 'Choose today or a future application deadline.';end if;
  if jsonb_typeof(p_data->'skills') <> 'array' then raise exception 'Skills must be a list.';end if;
  if p_action='create' then
   insert into public.team_posts(id,title,event_name,type,description,skills,year,department,gender,mode,location,college,seats,deadline,event_url,name,email)
   values(p_id,btrim(p_data->>'title'),btrim(p_data->>'event_name'),p_data->>'type',btrim(p_data->>'description'),array(select btrim(jsonb_array_elements_text(p_data->'skills'))),p_data->>'year',p_data->>'department',p_data->>'gender',p_data->>'mode',btrim(p_data->>'location'),btrim(p_data->>'college'),(p_data->>'seats')::integer,v_deadline,coalesce(p_data->>'event_url',''),btrim(p_data->>'name'),btrim(p_data->>'email'));
   insert into team_private.post_keys(post_id,key_hash) values(p_id,v_hash);
  else
   update public.team_posts set title=btrim(p_data->>'title'),event_name=btrim(p_data->>'event_name'),type=p_data->>'type',description=btrim(p_data->>'description'),skills=array(select btrim(jsonb_array_elements_text(p_data->'skills'))),year=p_data->>'year',department=p_data->>'department',gender=p_data->>'gender',mode=p_data->>'mode',location=btrim(p_data->>'location'),college=btrim(p_data->>'college'),seats=(p_data->>'seats')::integer,deadline=v_deadline,event_url=coalesce(p_data->>'event_url',''),name=btrim(p_data->>'name'),email=btrim(p_data->>'email'),updated_at=now() where id=p_id;
  end if;
 elsif p_action='delete' then delete from public.team_posts where id=p_id;
 elsif p_action='close' then update public.team_posts set status='closed',updated_at=now() where id=p_id and status<>'hidden';
 elsif p_action='reopen' then
  if exists(select 1 from public.team_posts where id=p_id and deadline<(now() at time zone 'Asia/Kolkata')::date) then raise exception 'Edit the expired deadline before reopening.';end if;
  update public.team_posts set status='open',updated_at=now() where id=p_id and status<>'hidden';
 end if;
 return p_id;
end;$$;
revoke all on function team_private.write_post(uuid,text,jsonb,text) from public;
grant execute on function team_private.write_post(uuid,text,jsonb,text) to anon,authenticated;
create function public.team_write(p_id uuid,p_key text,p_data jsonb,p_action text) returns uuid language sql security invoker set search_path='' as $$select team_private.write_post(p_id,p_key,p_data,p_action);$$;
revoke all on function public.team_write(uuid,text,jsonb,text) from public;
grant execute on function public.team_write(uuid,text,jsonb,text) to anon,authenticated;

create function team_private.report_post(p_post uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare v_ip text;
begin
 if not exists(select 1 from public.team_posts where id=p_post and status<>'hidden') then raise exception 'Opportunity not found.';end if;
 v_ip:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-forwarded-for','unknown');
 perform team_private.rate_check('report:'||md5(v_ip),20);
 insert into team_private.reports(post_id,reason) values(p_post,btrim(p_reason));
end;$$;
revoke all on function team_private.report_post(uuid,text) from public;
grant execute on function team_private.report_post(uuid,text) to anon,authenticated;
create function public.team_report(p_post uuid,p_reason text) returns void language sql security invoker set search_path='' as $$select team_private.report_post(p_post,p_reason);$$;
revoke all on function public.team_report(uuid,text) from public;
grant execute on function public.team_report(uuid,text) to anon,authenticated;
notify pgrst,'reload schema';
