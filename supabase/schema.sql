-- Gulxeb Fashion — database schema (Supabase / Postgres)
-- Admin = the Supabase Auth user whose email is in public.admins.

create extension if not exists pgcrypto;

create table if not exists public.admins (
  email text primary key
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins a join auth.users u on lower(u.email) = lower(a.email)
    where u.id = auth.uid() and u.email_confirmed_at is not null
  );
$$;

create table if not exists public.products (
  id          text primary key default ('gx-' || substr(gen_random_uuid()::text,1,8)),
  name        text not null,
  price       integer not null check (price >= 0),
  mrp         integer not null check (mrp >= 0),
  cat         text not null default 'Suits',
  gender      text not null default 'men' check (gender in ('men','women')),
  tone        text default '',
  badge       text default '',
  rating      numeric(2,1) default 4.8,
  reviews     integer default 0,
  short       text default '',
  description text default '',
  sizes       text[] not null default array['S','M','L','XL','XXL'],
  image_url   text,
  active      boolean not null default true,
  sort        integer not null default 100,
  created_at  timestamptz not null default now()
);

create table if not exists public.orders (
  id          uuid primary key default gen_random_uuid(),
  order_no    text unique not null,
  created_at  timestamptz not null default now(),
  name        text not null,
  phone       text not null,
  email       text not null,
  address     text not null,
  payment     text not null,
  items       jsonb not null,
  total       integer not null default 0,
  status      text not null default 'new'
              check (status in ('new','confirmed','paid','shipped','delivered','cancelled')),
  note        text default ''
);
create index if not exists orders_created_idx on public.orders (created_at desc);

-- Never trust prices from the browser: rebuild items + total from the products table.
create or replace function public.orders_price_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare it jsonb; p record; fixed jsonb := '[]'::jsonb; t integer := 0; q integer;
begin
  if tg_op = 'INSERT' and not public.is_admin() then
    new.status := 'new';
    new.note := '';
    for it in select * from jsonb_array_elements(new.items) loop
      select * into p from public.products where id = it->>'id' and active;
      if not found then raise exception 'Unknown product %', it->>'id'; end if;
      q := greatest(1, least(10, coalesce((it->>'qty')::int,1)));
      fixed := fixed || jsonb_build_object('id',p.id,'name',p.name,'size',it->>'size','qty',q,'price',p.price);
      t := t + p.price * q;
    end loop;
    if jsonb_array_length(fixed) = 0 then raise exception 'Empty order'; end if;
    new.items := fixed;
    new.total := t;
  end if;
  return new;
end $$;
drop trigger if exists orders_price_guard on public.orders;
create trigger orders_price_guard before insert on public.orders
  for each row execute function public.orders_price_guard();

-- Customer order lookup without exposing other people's orders
create or replace function public.order_status(p_order_no text, p_phone text)
returns table(order_no text, status text, created_at timestamptz, total integer, items jsonb)
language sql stable security definer set search_path = public as $$
  select o.order_no, o.status, o.created_at, o.total, o.items
  from public.orders o
  where o.order_no = p_order_no and right(regexp_replace(o.phone,'\D','','g'),10) = right(regexp_replace(p_phone,'\D','','g'),10);
$$;
grant execute on function public.order_status(text,text) to anon, authenticated;

alter table public.admins   enable row level security;
alter table public.products enable row level security;
alter table public.orders   enable row level security;

drop policy if exists "admins read self" on public.admins;
create policy "admins read self" on public.admins for select using (public.is_admin());

drop policy if exists "public reads active products" on public.products;
create policy "public reads active products" on public.products for select using (active or public.is_admin());
drop policy if exists "admin writes products" on public.products;
create policy "admin writes products" on public.products for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "anyone places orders" on public.orders;
create policy "anyone places orders" on public.orders for insert with check (true);
drop policy if exists "admin reads orders" on public.orders;
create policy "admin reads orders" on public.orders for select using (public.is_admin());
drop policy if exists "admin updates orders" on public.orders;
create policy "admin updates orders" on public.orders for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin deletes orders" on public.orders;
create policy "admin deletes orders" on public.orders for delete using (public.is_admin());

-- Product photos
insert into storage.buckets (id, name, public) values ('product-images','product-images', true)
  on conflict (id) do nothing;
drop policy if exists "public views product images" on storage.objects;
create policy "public views product images" on storage.objects for select using (bucket_id = 'product-images');
drop policy if exists "admin uploads product images" on storage.objects;
create policy "admin uploads product images" on storage.objects for insert with check (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "admin edits product images" on storage.objects;
create policy "admin edits product images" on storage.objects for update using (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "admin deletes product images" on storage.objects;
create policy "admin deletes product images" on storage.objects for delete using (bucket_id = 'product-images' and public.is_admin());

insert into public.admins (email) values ('gulxebfashion@gmail.com') on conflict do nothing;

-- Starter catalogue (same as the original site)
insert into public.products (id,name,price,mrp,cat,gender,tone,badge,rating,reviews,short,sizes,description,sort) values
 ('gx-01','Midnight Executive Suit',5999,7499,'Suits','men','','Bestseller',4.9,24,'4-piece • Imported premium',array['S','M','L','XL','XXL'],'Four-piece tailored set in imported premium fabric with signature silver detailing — cut for boardroom authority and evening presence alike.',1),
 ('gx-02','Silver Luxe Blazer',4999,6499,'Blazers','men','light','New',4.8,41,'Silver-laced trim',array['M','L','XL'],'A structured blazer traced with silver-laced trim. Lightweight shoulder, confident drape, made to lead the room.',2),
 ('gx-03','Navy Heritage Coat Pant',5499,6999,'Coat Pant','men','','',4.7,18,'Classic tailored cut',array['S','M','L','XL','XXL'],'Heritage navy coat-pant in a classic tailored cut. Built for weddings, board meets and every formal evening between.',3),
 ('gx-04','Royal Evening Blazer',4599,5999,'Blazers','men','light','Occasion',4.6,12,'Occasion edit',array['M','L','XL'],'A celebratory evening blazer with a royal accent — made to be noticed without trying.',4),
 ('gx-05','Silver Grace Suit',5799,6999,'Suits','women','women','New',4.9,33,'Premium imported fabric',array['S','M','L'],'Occasion suit in premium imported fabric with a graceful silver thread finish.',5),
 ('gx-06','Navy Signature Blazer',4799,6299,'Blazers','women','light women','',4.7,21,'Minimal luxury',array['M','L','XL','XXL'],'Minimal, luxurious navy blazer — clean lines, premium finish, effortless drape.',6)
on conflict (id) do nothing;
