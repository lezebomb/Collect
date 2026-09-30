-- Add collection metadata without discarding existing items.
alter table public.items
  add column if not exists currency text not null default 'CNY',
  add column if not exists price_cny numeric(12, 2),
  add column if not exists game_platform text,
  add column if not exists game_content_type text,
  add column if not exists game_edition text,
  add column if not exists game_play_status text;

update public.items set price_cny = price where price_cny is null and currency = 'CNY';

alter table public.items
  add constraint items_currency_check check (currency in ('CNY', 'USD', 'HKD', 'JPY', 'EUR', 'GBP')),
  add constraint items_price_cny_check check (price_cny is null or price_cny >= 0),
  add constraint items_game_platform_check check (game_platform is null or game_platform in ('Nintendo', 'PC')),
  add constraint items_game_content_type_check check (game_content_type is null or game_content_type in ('本体', 'DLC', '本体+DLC')),
  add constraint items_game_edition_check check (game_edition is null or game_edition in ('实体版', '数字版')),
  add constraint items_game_play_status_check check (game_play_status is null or game_play_status in ('吃灰中', '游玩中', '已通关', '全成就'));

create index if not exists items_user_purchase_date_idx on public.items (user_id, purchase_date desc);
create index if not exists items_user_category_idx on public.items (user_id, category);

create table public.user_categories (
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  created_at timestamptz not null default now(),
  primary key (user_id, name)
);
alter table public.user_categories enable row level security;
create policy user_categories_select_own on public.user_categories for select to authenticated using ((select auth.uid()) = user_id);
create policy user_categories_insert_own on public.user_categories for insert to authenticated with check ((select auth.uid()) = user_id);
create policy user_categories_delete_own on public.user_categories for delete to authenticated using ((select auth.uid()) = user_id);
grant select, insert, delete on public.user_categories to authenticated;
revoke all on public.user_categories from anon;

create table public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  show_price boolean not null default false,
  show_owned_days boolean not null default false,
  show_daily_cost boolean not null default false,
  wallpaper_url text,
  updated_at timestamptz not null default now()
);
alter table public.user_preferences enable row level security;
create policy user_preferences_select_own on public.user_preferences for select to authenticated using ((select auth.uid()) = user_id);
create policy user_preferences_insert_own on public.user_preferences for insert to authenticated with check ((select auth.uid()) = user_id);
create policy user_preferences_update_own on public.user_preferences for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
grant select, insert, update on public.user_preferences to authenticated;
revoke all on public.user_preferences from anon;
