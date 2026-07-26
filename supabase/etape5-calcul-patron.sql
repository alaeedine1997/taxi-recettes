-- ÉTAPE 5 — Le patron voit les fiches de recette de SES chauffeurs
-- (lecture seule, uniquement les chauffeurs de sa propre flotte).
-- À lancer dans l'éditeur SQL Supabase. Idempotent : relançable sans risque.
--
-- IMPORTANT : à lancer APRÈS avoir mis à jour l'app chauffeur (index.html),
-- qui filtre désormais sa lecture du carnet sur son propre user_id.

-- 0) Fonction dédiée, SECURITY DEFINER (= lit profiles en ignorant la RLS).
--    On crée un NOUVEAU nom exprès : une policy posée SUR profiles qui appellerait
--    une fonction NON security-definer provoquerait une récursion RLS infinie
--    (plus personne ne pourrait se connecter). On ne touche pas à my_role() existante.
create or replace function public.my_role_sd()
returns text
language sql
stable
security definer
set search_path = public
as $$ select role::text from public.profiles where id = auth.uid() $$;

revoke all on function public.my_role_sd() from public;
grant execute on function public.my_role_sd() to authenticated;

-- 1) Le patron peut lire les PROFILS des CHAUFFEURS de sa flotte
--    (pour afficher la liste de ses chauffeurs).
--    Limité au rôle 'chauffeur' : il n'a pas à voir les identifiants de
--    connexion des autres patrons ni d'un super-admin.
drop policy if exists profiles_patron_read on public.profiles;
create policy profiles_patron_read on public.profiles
  for select
  to authenticated
  using (
    public.my_role_sd() = 'patron'
    and role::text = 'chauffeur'
    and fleet_id is not null
    and fleet_id = public.my_fleet()
  );

-- 2) Le patron peut lire les CARNETS des chauffeurs de sa flotte.
--    LECTURE SEULE : aucune policy d'écriture n'est ajoutée -> il ne peut pas
--    modifier le carnet d'un chauffeur (seul le chauffeur écrit le sien).
drop policy if exists carnets_patron_read on public.carnets;
create policy carnets_patron_read on public.carnets
  for select
  to authenticated
  using (
    public.my_role_sd() = 'patron'
    and exists (
      select 1
      from public.profiles p
      where p.id = carnets.user_id
        and p.role::text = 'chauffeur'
        and p.fleet_id is not null
        and p.fleet_id = public.my_fleet()
    )
  );

-- Vérification (doit lister les 2 policies + la fonction en security definer) :
-- select tablename, policyname, cmd from pg_policies
--   where policyname in ('profiles_patron_read','carnets_patron_read');
-- select proname, prosecdef from pg_proc where proname in ('my_role','my_role_sd','my_fleet');
