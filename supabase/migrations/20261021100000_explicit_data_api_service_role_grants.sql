-- Keep the server-side Data API reads used by PatriGest independent from
-- Supabase's automatic privileges for newly created public tables.
grant select on table
  public.account_requests,
  public.application_user_authorizations,
  public.bank_statements,
  public.categories,
  public.management_report_account_selections,
  public.management_report_approvals,
  public.management_report_difficulties,
  public.management_report_documents,
  public.management_report_transmissions,
  public.management_reports,
  public.platform_administrators,
  public.profiles,
  public.protected_person_access,
  public.protected_person_invitations,
  public.protected_persons,
  public.transaction_documents
to service_role;

-- The account-request invitation workflow only needs to mark the invitation
-- as consumed. No other direct service-role update is introduced here.
grant update (invitation_used_at)
on table public.account_requests
to service_role;
