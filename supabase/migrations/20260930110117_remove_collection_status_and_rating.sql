-- Every collection item is owned. Gameplay progress remains in game_play_status.
alter table public.items
  drop column if exists status,
  drop column if exists rating;
