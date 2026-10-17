-- 0047 handtekening (14c, 5/6): bon_ondertekenen (nacontrole en recht: 0048). Bon, regel, rekening op slot. Na 0046. Rollback: rollbacks/0047_rollback.sql
begin;
do $m$ begin if to_regproc('public.teken_wacht') is null or to_regproc('public.bon_ondertekenen') is not null then
  raise exception '0047 vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;

create function public.bon_ondertekenen(p_bon uuid, p_naam text, p_handtekening text, p_vingerafdruk text) returns text
language plpgsql security definer set search_path = public, pg_temp as $f$
declare r uuid := my_restaurant_id(); b receipts; n int; k int; x int; c uuid; m text; st text; nm text := btrim(coalesce(p_naam,''));
begin
  if r is null or not has_perm('MANAGE_RECEIPTS') then raise exception 'Geen recht' using errcode = '42501'; end if;
  if char_length(nm) not between 2 and 100 then raise exception 'Naam ongeldig' using errcode = '22023'; end if;
  if not png_geldig(p_handtekening) then raise exception 'Geen PNG' using errcode = '22023'; end if;
  select * into b from receipts where id = p_bon and restaurant_id = r for update;
  if not found then raise exception 'Bon niet gevonden' using errcode = 'P0002'; end if;
  if not (feature_aan(r, 'approval') and feature_aan(r, 'signature')) then raise exception 'Module staat uit' using errcode = '42501'; end if;
  perform from approvals where receipt_id = p_bon and status = 'pending' for update;
  select count(*), count(distinct (method, company_id)), min(method), min(company_id::text)::uuid into n, k, m, c
    from approvals where receipt_id = p_bon and status = 'pending';
  if b.status <> 'pending_approval' or k <> 1 or m <> 'signature' then raise exception 'Bon wacht niet op handtekening' using errcode = '55000'; end if;
  perform from open_tabs where id = b.open_tab_id and company_id = c for share;
  if not found then raise exception 'Bedrijf verschilt' using errcode = '22000'; end if;
  if p_vingerafdruk is distinct from bon_vingerafdruk(p_bon) then raise exception 'De bon is gewijzigd' using errcode = '22000'; end if;
  st := coalesce((select case when not auto_lock then 'approved' end from approval_settings where company_id = c), 'locked');
  perform set_config('polder.ondertekening', p_bon::text, true);
  update receipts set status = st where id = p_bon;
  update approvals set status = 'approved', approved_by = nm, approved_at = now(), signature_data = p_handtekening, metadata =
    coalesce(metadata, '{}') || jsonb_build_object('gestart_door', auth.uid(), 'vingerafdruk', p_vingerafdruk)
    where receipt_id = p_bon and status = 'pending';
  get diagnostics x = row_count;
  if x <> n then raise exception 'Regel gewijzigd' using errcode = '55000'; end if;
  perform set_config('polder.ondertekening', '', true);
  return st;
end $f$;

revoke all on function public.bon_ondertekenen(uuid,text,text,text) from public, anon, authenticated, service_role;
commit;
