export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

type ProtectedPersonStatus = "active" | "archived";
export type MeasureType =
  | "safeguard_of_justice"
  | "safeguard_with_special_mandate"
  | "simple_curatorship"
  | "reinforced_curatorship"
  | "guardianship"
  | "future_protection_mandate"
  | "family_authorization"
  | "judicial_support_measure";
type ManagementPeriodStatus = "open" | "closed";
export type FinancialAccountType = "checking" | "livret_a" | "ldds" | "csl" | "lep" | "pel" | "term_account" | "life_insurance" | "other_investment" | "securities_account";
type FinancialAccountStatus = "active" | "closed";
export type CategoryUsage = "income" | "expense" | "both";
export type TransactionType = "income" | "expense" | "transfer_in" | "transfer_out";
export type AccountingNature = "ordinary" | "capital_movement";
export type DossierAccessRole = "owner" | "manager" | "read_only";
export type SharedAccessRole = Exclude<DossierAccessRole, "owner">;
type AccountRequestStatus = "pending" | "approved" | "rejected";
export type ApplicationUserAuthorizationStatus = "pending" | "active" | "rejected";
export type AccountMode = "autonomous" | "collaborator";
export type AccountTrialStateName = "not_authorized" | "terms_required" | "awaiting_activation" | "active" | "suspended" | "deletion_due" | "subscribed" | "legacy_access";
export type SubscriptionPlanKey = "essential" | "comfort" | "premium";
export type SubscriptionDossierCapacityKey = "included" | "five" | "ten" | "custom";
export type AccountSubscriptionStatus = "development" | "active" | "past_due" | "canceled" | "ended";
export type AccountEntitlementAccessSource = "none" | "commercial" | "administrative" | "trial" | "legacy" | "development" | "shared_access";
export type AdministrativeBillingPeriod = "monthly" | "annual";
export type AdministrativeDossierCapacityKey = "included" | "five" | "ten";
export type AdministrativeEntitlementBlockCode =
  | "platform_administrator"
  | "authorization_inactive"
  | "account_not_autonomous"
  | "purge_in_progress"
  | "commercial_subscription_active"
  | "active_override_must_be_revoked"
  | "entitlement_base_required";
export type ReleaseNotificationDeliveryKind = "test" | "global";
export type ReleaseNotificationStatus = "pending" | "sending" | "sent" | "failed";
export type PropertyType = "house" | "apartment" | "land" | "commercial" | "other";
export type PropertyEntryMode = "acquisition" | "inheritance" | "donation" | "other";
export type PropertyStatus = "active" | "disposed";
export type PropertyEventType = "acquisition" | "sale" | "inheritance" | "donation" | "significant_change";
export type DebtType = "bank_loan" | "tax_debt" | "institution_debt" | "personal_debt" | "other";
export type DebtStatus = "active" | "settled";
export type PatrimonyAbsenceCategory = "real_estate" | "active_debt";
export type BankReconciliationStatus = "draft" | "validated";
export type ManagementReportStatus = "draft" | "ready" | "generated" | "finalized" | "transmitted" | "approved" | "difficulty";
export type ManagementReportDocumentType = "management_report_draft" | "management_report" | "approval_certificate" | "difficulty_report";
export type ManagementReportTransmissionMethod = "postal_mail" | "hand_delivery" | "email" | "external_platform" | "other";
export type ManagementReportAccountSelectionMode = "included_manual" | "excluded_manual";

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: { id: string; first_name: string | null; last_name: string | null; last_seen_version: string | null; created_at: string; updated_at: string };
        Insert: { id: string; first_name?: string | null; last_name?: string | null; last_seen_version?: string | null; created_at?: string; updated_at?: string };
        Update: { first_name?: string | null; last_name?: string | null; last_seen_version?: string | null; updated_at?: string };
        Relationships: [];
      };
      application_user_authorizations: {
        Row: { user_id: string; status: ApplicationUserAuthorizationStatus; account_mode: AccountMode | null; status_changed_at: string; status_changed_by: string | null; created_at: string; updated_at: string };
        Insert: { user_id: string; status?: ApplicationUserAuthorizationStatus; account_mode?: AccountMode | null; status_changed_at?: string; status_changed_by?: string | null; created_at?: string; updated_at?: string };
        Update: { status?: ApplicationUserAuthorizationStatus; account_mode?: AccountMode | null; status_changed_at?: string; status_changed_by?: string | null; updated_at?: string };
        Relationships: [];
      };
      account_subscriptions: {
        Row: {
          id: string;
          owner_id: string;
          plan_key: SubscriptionPlanKey | null;
          dossier_capacity_key: SubscriptionDossierCapacityKey | null;
          custom_active_dossier_limit: number | null;
          status: AccountSubscriptionStatus;
          started_at: string;
          current_period_started_at: string | null;
          current_period_ends_at: string | null;
          canceled_at: string | null;
          ended_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          owner_id: string;
          plan_key?: SubscriptionPlanKey | null;
          dossier_capacity_key?: SubscriptionDossierCapacityKey | null;
          custom_active_dossier_limit?: number | null;
          status?: AccountSubscriptionStatus;
          started_at?: string;
          current_period_started_at?: string | null;
          current_period_ends_at?: string | null;
          canceled_at?: string | null;
          ended_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["account_subscriptions"]["Insert"]>;
        Relationships: [];
      };
      protected_persons: {
        Row: {
          id: string; owner_id: string; first_name: string; last_name: string;
          birth_name: string | null; birth_date: string | null; birth_place: string | null;
          address_line1: string | null; address_line2: string | null; postal_code: string | null;
          city: string | null; country: string; phone: string | null; email: string | null;
          residence_address_line1: string | null; residence_address_line2: string | null;
          residence_postal_code: string | null; residence_city: string | null; residence_country: string | null;
          notes: string | null; status: ProtectedPersonStatus; created_at: string;
          updated_at: string; archived_at: string | null; archive_revision: number;
        };
        Insert: {
          id?: string; owner_id: string; first_name: string; last_name: string;
          birth_name?: string | null; birth_date?: string | null; birth_place?: string | null;
          address_line1?: string | null; address_line2?: string | null; postal_code?: string | null;
          city?: string | null; country?: string; phone?: string | null; email?: string | null;
          residence_address_line1?: string | null; residence_address_line2?: string | null;
          residence_postal_code?: string | null; residence_city?: string | null; residence_country?: string | null;
          notes?: string | null; status?: ProtectedPersonStatus; created_at?: string;
          updated_at?: string; archived_at?: string | null; archive_revision?: number;
        };
        Update: Partial<Database["public"]["Tables"]["protected_persons"]["Insert"]>;
        Relationships: [];
      };
      protection_measures: {
        Row: {
          id: string; protected_person_id: string; measure_type: MeasureType;
          start_date: string | null; end_date: string | null; decision_date: string | null;
          court_name: string | null; court_city: string | null; case_reference: string | null;
          court_cabinet: string | null;
          judge_name: string | null; notary_name: string | null; notes: string | null;
          representative_first_name: string | null; representative_last_name: string | null;
          representative_appointment_date: string | null;
          representative_address_line1: string | null; representative_address_line2: string | null;
          representative_postal_code: string | null; representative_city: string | null;
          representative_country: string | null; representative_phone: string | null; representative_email: string | null;
          active: boolean; created_at: string; updated_at: string;
        };
        Insert: {
          id?: string; protected_person_id: string; measure_type: MeasureType;
          start_date?: string | null; end_date?: string | null; decision_date?: string | null;
          court_name?: string | null; court_city?: string | null; case_reference?: string | null;
          court_cabinet?: string | null;
          judge_name?: string | null; notary_name?: string | null; notes?: string | null;
          representative_first_name?: string | null; representative_last_name?: string | null;
          representative_appointment_date?: string | null;
          representative_address_line1?: string | null; representative_address_line2?: string | null;
          representative_postal_code?: string | null; representative_city?: string | null;
          representative_country?: string | null; representative_phone?: string | null; representative_email?: string | null;
          active?: boolean; created_at?: string; updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["protection_measures"]["Insert"]>;
        Relationships: [{ foreignKeyName: "protection_measures_protected_person_id_fkey"; columns: ["protected_person_id"]; isOneToOne: false; referencedRelation: "protected_persons"; referencedColumns: ["id"] }];
      };
      management_periods: {
        Row: {
          id: string; protected_person_id: string; start_date: string; end_date: string;
          status: ManagementPeriodStatus; notes: string | null; created_at: string;
          updated_at: string; closed_at: string | null;
        };
        Insert: {
          id?: string; protected_person_id: string; start_date: string; end_date: string;
          status?: ManagementPeriodStatus; notes?: string | null; created_at?: string;
          updated_at?: string; closed_at?: string | null;
        };
        Update: Partial<Database["public"]["Tables"]["management_periods"]["Insert"]>;
        Relationships: [{ foreignKeyName: "management_periods_protected_person_id_fkey"; columns: ["protected_person_id"]; isOneToOne: false; referencedRelation: "protected_persons"; referencedColumns: ["id"] }];
      };
      financial_accounts: {
        Row: {
          id: string; protected_person_id: string; account_type: FinancialAccountType;
          institution_name: string; account_name: string; account_reference: string | null;
          opening_date: string | null; closing_date: string | null; initial_balance: number;
          initial_balance_date: string; notes: string | null; status: FinancialAccountStatus;
          created_at: string; updated_at: string;
        };
        Insert: {
          id?: string; protected_person_id: string; account_type: FinancialAccountType;
          institution_name: string; account_name: string; account_reference?: string | null;
          opening_date?: string | null; closing_date?: string | null; initial_balance?: number;
          initial_balance_date: string; notes?: string | null; status?: FinancialAccountStatus;
          created_at?: string; updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["financial_accounts"]["Insert"]>;
        Relationships: [{ foreignKeyName: "financial_accounts_protected_person_id_fkey"; columns: ["protected_person_id"]; isOneToOne: false; referencedRelation: "protected_persons"; referencedColumns: ["id"] }];
      };
      account_valuations: {
        Row: { id: string; financial_account_id: string; valuation_date: string; value: number; comment: string | null; created_at: string };
        Insert: { id?: string; financial_account_id: string; valuation_date: string; value: number; comment?: string | null; created_at?: string };
        Update: Partial<Database["public"]["Tables"]["account_valuations"]["Insert"]>;
        Relationships: [{ foreignKeyName: "account_valuations_financial_account_id_fkey"; columns: ["financial_account_id"]; isOneToOne: false; referencedRelation: "financial_accounts"; referencedColumns: ["id"] }];
      };
      platform_administrators: {
        Row: { user_id: string; appointed_by: string | null; created_at: string };
        Insert: { user_id: string; appointed_by?: string | null; created_at?: string };
        Update: never;
        Relationships: [];
      };
      account_requests: {
        Row: { id: string; email: string; first_name: string; last_name: string; message: string | null; status: AccountRequestStatus; invitation_token_hash: string | null; invitation_expires_at: string | null; invitation_used_at: string | null; created_at: string; reviewed_at: string | null; reviewed_by: string | null };
        Insert: { id?: string; email: string; first_name: string; last_name: string; message?: string | null; status?: AccountRequestStatus; invitation_token_hash?: string | null; invitation_expires_at?: string | null; invitation_used_at?: string | null; created_at?: string; reviewed_at?: string | null; reviewed_by?: string | null };
        Update: Partial<Database["public"]["Tables"]["account_requests"]["Insert"]>;
        Relationships: [];
      };
      protected_person_access: {
        Row: { id: string; protected_person_id: string; user_id: string; role: SharedAccessRole; invited_by: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; user_id: string; role: SharedAccessRole; invited_by: string | null; created_at?: string; updated_at?: string };
        Update: { role?: SharedAccessRole; updated_at?: string };
        Relationships: [];
      };
      protected_person_invitations: {
        Row: { id: string; protected_person_id: string; email: string; role: SharedAccessRole; token_hash: string; expires_at: string; accepted_at: string | null; revoked_at: string | null; declined_at: string | null; declined_by: string | null; invited_by: string | null; created_at: string };
        Insert: { id?: string; protected_person_id: string; email: string; role: SharedAccessRole; token_hash: string; expires_at: string; accepted_at?: string | null; revoked_at?: string | null; declined_at?: string | null; declined_by?: string | null; invited_by: string | null; created_at?: string };
        Update: { role?: SharedAccessRole; expires_at?: string; accepted_at?: string | null; revoked_at?: string | null; declined_at?: string | null; declined_by?: string | null };
        Relationships: [];
      };
      protected_person_share_limit_configuration: {
        Row: { configuration_key: string; manager_limit: number; read_only_limit: number; updated_at: string };
        Insert: { configuration_key: string; manager_limit: number; read_only_limit: number; updated_at?: string };
        Update: { manager_limit?: number; read_only_limit?: number; updated_at?: string };
        Relationships: [];
      };
      protected_person_archive_changes: {
        Row: { id: string; protected_person_id: string; old_status: ProtectedPersonStatus; new_status: ProtectedPersonStatus; changed_by: string; changed_at: string; reason: string };
        Insert: never;
        Update: never;
        Relationships: [{ foreignKeyName: "protected_person_archive_changes_protected_person_id_fkey"; columns: ["protected_person_id"]; isOneToOne: false; referencedRelation: "protected_persons"; referencedColumns: ["id"] }];
      };
      categories: {
        Row: { id: string; owner_id: string | null; name: string; usage: CategoryUsage; is_system: boolean; active: boolean; official_code: string | null; official_section: string | null; official_group: string | null; official_order: number | null; official_category_id: string | null; requires_precision: boolean; created_at: string; updated_at: string };
        Insert: { id?: string; owner_id?: string | null; name: string; usage: CategoryUsage; is_system?: boolean; active?: boolean; official_code?: string | null; official_section?: string | null; official_group?: string | null; official_order?: number | null; official_category_id?: string | null; created_at?: string; updated_at?: string };
        Update: { name?: string; usage?: CategoryUsage; active?: boolean; official_category_id?: string | null; updated_at?: string };
        Relationships: [{ foreignKeyName: "categories_official_category_id_fkey"; columns: ["official_category_id"]; isOneToOne: false; referencedRelation: "categories"; referencedColumns: ["id"] }];
      };
      transfers: {
        Row: { id: string; protected_person_id: string; source_account_id: string; destination_account_id: string; transfer_date: string; amount: number; label: string | null; comment: string | null; created_at: string; updated_at: string; revision: number; cancelled_at: string | null; cancelled_by: string | null };
        Insert: { id?: string; protected_person_id: string; source_account_id: string; destination_account_id: string; transfer_date: string; amount: number; label?: string | null; comment?: string | null; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["transfers"]["Insert"]>;
        Relationships: [];
      };
      transactions: {
        Row: { id: string; financial_account_id: string; transaction_date: string; transaction_type: TransactionType; label: string; amount: number; category_id: string | null; transfer_id: string | null; proof_reference: string | null; comment: string | null; accounting_nature: AccountingNature | null; official_category_id: string | null; classification_precision: string | null; created_at: string; updated_at: string; revision: number; cancelled_at: string | null; cancelled_by: string | null };
        Insert: { id?: string; financial_account_id: string; transaction_date: string; transaction_type: TransactionType; label: string; amount: number; category_id?: string | null; transfer_id?: string | null; proof_reference?: string | null; comment?: string | null; accounting_nature?: AccountingNature | null; official_category_id?: string | null; classification_precision?: string | null; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["transactions"]["Insert"]>;
        Relationships: [{ foreignKeyName: "transactions_official_category_id_fkey"; columns: ["official_category_id"]; isOneToOne: false; referencedRelation: "categories"; referencedColumns: ["id"] }];
      };
      proof_reference_counters: {
        Row: { protected_person_id: string; reference_year: number; last_number: number; updated_at: string };
        Insert: { protected_person_id: string; reference_year: number; last_number: number; updated_at?: string };
        Update: { last_number?: number; updated_at?: string };
        Relationships: [];
      };
      proof_reference_assignments: {
        Row: { id: string; transaction_id: string; protected_person_id: string; reference_year: number; reference_number: number; proof_reference: string; created_at: string; started_revision: number | null; ended_revision: number | null; ended_at: string | null; ended_by_change_id: string | null };
        Insert: { id?: string; transaction_id: string; protected_person_id: string; reference_year: number; reference_number: number; proof_reference: string; created_at?: string; started_revision?: number | null; ended_revision?: number | null; ended_at?: string | null; ended_by_change_id?: string | null };
        Update: never;
        Relationships: [];
      };
      transaction_documents: {
        Row: { id: string; transaction_id: string; storage_path: string; file_name: string; mime_type: string; file_size: number; created_by: string; created_at: string; updated_at: string; proof_document_id: string | null; proof_version_id: string | null };
        Insert: { id?: string; transaction_id: string; storage_path: string; file_name: string; mime_type: string; file_size: number; created_by: string; created_at?: string; updated_at?: string; proof_document_id?: string | null; proof_version_id?: string | null };
        Update: { file_name?: string; mime_type?: string; file_size?: number; created_by?: string; updated_at?: string };
        Relationships: [];
      };
      transaction_changes: {
        Row: { id: string; protected_person_id: string; transaction_id: string; request_id: string; change_kind: "correction" | "cancellation"; reason: string; revision_before: number; revision_after: number; previous_values: Json; new_values: Json; changed_by: string | null; changed_by_name: string; changed_at: string };
        Insert: never; Update: never; Relationships: [];
      };
      transfer_changes: {
        Row: { id: string; protected_person_id: string; transfer_id: string; request_id: string; change_kind: "correction" | "cancellation"; reason: string; revision_before: number; revision_after: number; previous_values: Json; new_values: Json; changed_by: string | null; changed_by_name: string; changed_at: string };
        Insert: never; Update: never; Relationships: [];
      };
      transaction_banking_impacts: {
        Row: { id: string; protected_person_id: string; transaction_change_id: string | null; transfer_change_id: string | null; transaction_id: string | null; transfer_id: string | null; financial_account_id: string; effective_date: string; impact_kind: "reverse_previous" | "apply_current"; signed_amount: number; created_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      transaction_document_history: {
        Row: { id: string; protected_person_id: string; transaction_id: string; transaction_change_id: string; original_document_id: string; storage_path: string; file_name: string; mime_type: string; file_size: number; original_created_by: string | null; original_created_at: string; original_updated_at: string; archived_by: string | null; archived_by_name: string; archived_at: string; archive_reason: string; proof_document_id: string | null; proof_version_id: string | null; expense_reference_assignment_id: string | null; proof_reference: string | null; availability_status: "unverified" | "available" | "missing" };
        Insert: never; Update: never; Relationships: [];
      };
      transaction_proof_documents: {
        Row: { id: string; protected_person_id: string; transaction_id: string; expense_reference_assignment_id: string; proof_reference: string; lifecycle_status: "current" | "historical"; created_by: string | null; created_at: string; detached_at: string | null; detached_by_change_id: string | null };
        Insert: never; Update: never; Relationships: [];
      };
      transaction_proof_versions: {
        Row: { id: string; proof_document_id: string; version_number: number; storage_path: string; path_kind: "legacy" | "versioned"; lifecycle_state: "current" | "historical" | "superseded_pending_deletion" | "deleted"; availability_status: "unverified" | "available" | "missing"; file_name: string; mime_type: string; file_size: number; sha256: string | null; storage_object_id: string | null; storage_object_version: string | null; created_by: string | null; created_at: string; superseded_at: string | null; replacement_operation_id: string | null };
        Insert: never; Update: never; Relationships: [];
      };
      transaction_proof_replacement_retirements: {
        Row: { id: string; proof_document_id: string; superseded_version_id: string; replacement_version_id: string; operation_id: string; state: "pending_secure_deletion" | "completed" | "attention_required"; created_at: string; completed_at: string | null };
        Insert: never; Update: never; Relationships: [];
      };
      real_estate_properties: {
        Row: { id: string; protected_person_id: string; property_type: PropertyType; designation: string; address_line1: string | null; address_line2: string | null; postal_code: string | null; city: string | null; country: string; entry_date: string | null; entry_mode: PropertyEntryMode | null; estimated_value: number | null; valuation_date: string | null; status: PropertyStatus; disposal_date: string | null; notes: string | null; created_at: string; updated_at: string; archive_revision: number; archived_at: string | null; archived_by: string | null; archive_reason: string | null };
        Insert: { id?: string; protected_person_id: string; property_type: PropertyType; designation: string; address_line1?: string | null; address_line2?: string | null; postal_code?: string | null; city?: string | null; country?: string; entry_date?: string | null; entry_mode?: PropertyEntryMode | null; estimated_value?: number | null; valuation_date?: string | null; status?: PropertyStatus; disposal_date?: string | null; notes?: string | null; created_at?: string; updated_at?: string; archive_revision?: number; archived_at?: string | null; archived_by?: string | null; archive_reason?: string | null };
        Update: Partial<Database["public"]["Tables"]["real_estate_properties"]["Insert"]>;
        Relationships: [];
      };
      property_events: {
        Row: { id: string; property_id: string; protected_person_id: string; event_type: PropertyEventType; event_date: string; description: string; amount: number | null; document_reference: string | null; created_at: string; revision: number; cancelled_at: string | null; cancelled_by: string | null; cancellation_reason: string | null };
        Insert: { id?: string; property_id: string; protected_person_id: string; event_type: PropertyEventType; event_date: string; description: string; amount?: number | null; document_reference?: string | null; created_at?: string; revision?: number; cancelled_at?: string | null; cancelled_by?: string | null; cancellation_reason?: string | null };
        Update: Partial<Database["public"]["Tables"]["property_events"]["Insert"]>;
        Relationships: [];
      };
      property_event_changes: {
        Row: { id: string; property_event_id: string; property_id: string; protected_person_id: string; change_type: "correction" | "sale_date_correction" | "cancellation" | "restoration"; old_values: Json; new_values: Json; reason: string; changed_by: string; changed_by_name: string; changed_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      property_archive_changes: {
        Row: { id: string; property_id: string; protected_person_id: string; operation: "archive" | "restore"; old_values: Json; new_values: Json; reason: string; changed_by: string; changed_by_name: string; changed_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      property_sale_price_corrections: {
        Row: { id: string; property_event_id: string; property_id: string; protected_person_id: string; old_price: number; new_price: number; reason: string; corrected_by: string; corrected_by_name: string; corrected_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      patrimony_absence_confirmations: {
        Row: { protected_person_id: string; category: PatrimonyAbsenceCategory; confirmed_at: string; confirmed_by: string; confirmed_by_name: string };
        Insert: { protected_person_id: string; category: PatrimonyAbsenceCategory };
        Update: never;
        Relationships: [];
      };
      debts: {
        Row: { id: string; protected_person_id: string; creditor: string; debt_type: DebtType; designation: string; start_date: string | null; initial_amount: number | null; initial_duration_months: number | null; monthly_payment: number | null; interest_rate: number | null; current_balance: number | null; current_balance_date: string | null; remaining_duration_months: number | null; status: DebtStatus; settled_at: string | null; notes: string | null; revision: number; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; creditor: string; debt_type: DebtType; designation: string; start_date?: string | null; initial_amount?: number | null; initial_duration_months?: number | null; monthly_payment?: number | null; interest_rate?: number | null; current_balance?: number | null; current_balance_date?: string | null; remaining_duration_months?: number | null; status?: DebtStatus; settled_at?: string | null; notes?: string | null; revision?: number; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["debts"]["Insert"]>;
        Relationships: [];
      };
      debt_balances: {
        Row: { id: string; debt_id: string; balance_date: string; remaining_balance: number; remaining_duration_months: number | null; revision: number; cancelled_at: string | null; cancelled_by: string | null; cancellation_reason: string | null; created_at: string };
        Insert: { id?: string; debt_id: string; balance_date: string; remaining_balance: number; remaining_duration_months?: number | null; revision?: number; cancelled_at?: string | null; cancelled_by?: string | null; cancellation_reason?: string | null; created_at?: string };
        Update: Partial<Database["public"]["Tables"]["debt_balances"]["Insert"]>;
        Relationships: [];
      };
      debt_balance_changes: {
        Row: { id: string; debt_balance_id: string; debt_id: string; protected_person_id: string; change_type: "correction" | "cancellation"; old_values: Json; new_values: Json; reason: string; revision_from: number; revision_to: number; changed_by: string; changed_by_name: string; changed_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      debt_status_changes: {
        Row: { id: string; debt_id: string; protected_person_id: string; change_type: "settlement"; old_status: DebtStatus; new_status: DebtStatus; old_settled_at: string | null; new_settled_at: string | null; balance_id: string; old_values: Json; new_values: Json; reason: string; revision_from: number; revision_to: number; changed_by: string; changed_by_name: string; changed_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      bank_statements: {
        Row: { id: string; financial_account_id: string; statement_start_date: string | null; statement_end_date: string; statement_balance: number | null; storage_path: string; original_file_name: string | null; mime_type: string | null; file_size: number | null; note: string | null; created_by: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; financial_account_id: string; statement_start_date?: string | null; statement_end_date: string; statement_balance?: number | null; storage_path: string; original_file_name?: string | null; mime_type?: string | null; file_size?: number | null; note?: string | null; created_by: string; created_at?: string; updated_at?: string };
        Update: { statement_start_date?: string | null; statement_end_date?: string; statement_balance?: number | null; original_file_name?: string | null; mime_type?: string | null; file_size?: number | null; note?: string | null; updated_at?: string };
        Relationships: [];
      };
      release_notifications: {
        Row: { id: string; version: string; user_id: string; email_snapshot: string; delivery_kind: ReleaseNotificationDeliveryKind; status: ReleaseNotificationStatus; provider_message_id: string | null; attempt_count: number; last_error_safe: string | null; requested_by: string | null; created_at: string; sent_at: string | null; updated_at: string };
        Insert: { id?: string; version: string; user_id: string; email_snapshot: string; delivery_kind: ReleaseNotificationDeliveryKind; status?: ReleaseNotificationStatus; provider_message_id?: string | null; attempt_count?: number; last_error_safe?: string | null; requested_by?: string | null; created_at?: string; sent_at?: string | null; updated_at?: string };
        Update: { email_snapshot?: string; status?: ReleaseNotificationStatus; provider_message_id?: string | null; attempt_count?: number; last_error_safe?: string | null; requested_by?: string | null; sent_at?: string | null; updated_at?: string };
        Relationships: [];
      };
      bank_reconciliations: {
        Row: { id: string; bank_statement_id: string; status: BankReconciliationStatus; reconciliation_mode: "simple" | "complete"; calculated_balance: number | null; difference: number | null; outstanding_debits: number | null; outstanding_credits: number | null; explained_bank_balance: number | null; residual_difference: number | null; created_by: string | null; created_at: string; updated_at: string; validated_at: string | null; validated_by: string | null };
        Insert: { id?: string; bank_statement_id: string; status?: BankReconciliationStatus; reconciliation_mode?: "simple" | "complete"; calculated_balance?: number | null; difference?: number | null; outstanding_debits?: number | null; outstanding_credits?: number | null; explained_bank_balance?: number | null; residual_difference?: number | null; created_by: string; created_at?: string; updated_at?: string; validated_at?: string | null; validated_by?: string | null };
        Update: { status?: BankReconciliationStatus; reconciliation_mode?: "simple" | "complete"; calculated_balance?: number | null; difference?: number | null; outstanding_debits?: number | null; outstanding_credits?: number | null; explained_bank_balance?: number | null; residual_difference?: number | null; updated_at?: string; validated_at?: string | null; validated_by?: string | null };
        Relationships: [];
      };
      bank_reconciliation_outstanding_transactions: {
        Row: { id: string; bank_reconciliation_id: string; transaction_id: string | null; transaction_id_snapshot: string; transaction_date_snapshot: string | null; transaction_type_snapshot: TransactionType | null; amount_snapshot: number | null; label_snapshot: string | null; created_by: string | null; created_at: string };
        Insert: { id?: string; bank_reconciliation_id: string; transaction_id: string; transaction_id_snapshot: string; transaction_date_snapshot?: string | null; transaction_type_snapshot?: TransactionType | null; amount_snapshot?: number | null; label_snapshot?: string | null; created_by: string; created_at?: string };
        Update: { transaction_id?: string | null; transaction_date_snapshot?: string | null; transaction_type_snapshot?: TransactionType | null; amount_snapshot?: number | null; label_snapshot?: string | null; created_by?: string | null };
        Relationships: [];
      };
      transaction_banking_impact_acknowledgements: {
        Row: { id: string; impact_id: string; bank_reconciliation_id: string; justification: string; acknowledged_by: string | null; acknowledged_by_name: string; acknowledged_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      management_reports: {
        Row: { id: string; protected_person_id: string; management_period_id: string | null; report_year: number; period_start: string; period_end: string; status: ManagementReportStatus; residence_changed: boolean | null; representative_address_changed: boolean | null; real_estate_confirmed: boolean | null; financial_investments_confirmed: boolean | null; observations: string | null; signature_place: string | null; generated_at: string | null; finalized_at: string | null; transmitted_at: string | null; approved_at: string | null; difficulty_reported_at: string | null; refresh_required_at: string | null; created_by: string; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; management_period_id?: string | null; report_year: number; period_start: string; period_end: string; status?: ManagementReportStatus; residence_changed?: boolean | null; representative_address_changed?: boolean | null; real_estate_confirmed?: boolean | null; financial_investments_confirmed?: boolean | null; observations?: string | null; signature_place?: string | null; generated_at?: string | null; finalized_at?: string | null; transmitted_at?: string | null; approved_at?: string | null; difficulty_reported_at?: string | null; refresh_required_at?: string | null; created_by: string; created_at?: string; updated_at?: string };
        Update: { status?: ManagementReportStatus; residence_changed?: boolean | null; representative_address_changed?: boolean | null; real_estate_confirmed?: boolean | null; financial_investments_confirmed?: boolean | null; observations?: string | null; signature_place?: string | null; generated_at?: string | null; finalized_at?: string | null; transmitted_at?: string | null; approved_at?: string | null; difficulty_reported_at?: string | null; refresh_required_at?: string | null; updated_at?: string };
        Relationships: [];
      };
      management_report_documents: {
        Row: { id: string; management_report_id: string; document_type: ManagementReportDocumentType; storage_path: string; file_name: string; mime_type: string; file_size: number; preview_snapshot: Json | null; snapshot_schema_version: number | null; generated_by: string; created_at: string };
        Insert: { id?: string; management_report_id: string; document_type: ManagementReportDocumentType; storage_path: string; file_name: string; mime_type?: string; file_size: number; preview_snapshot?: Json | null; snapshot_schema_version?: number | null; generated_by: string; created_at?: string };
        Update: never;
        Relationships: [];
      };
      management_report_account_selections: {
        Row: { id: string; management_report_id: string; financial_account_id: string; selection_mode: ManagementReportAccountSelectionMode; reason: string; created_by: string; created_at: string; updated_at: string };
        Insert: { id?: string; management_report_id: string; financial_account_id: string; selection_mode: ManagementReportAccountSelectionMode; reason: string; created_by: string; created_at?: string; updated_at?: string };
        Update: { selection_mode?: ManagementReportAccountSelectionMode; reason?: string; updated_at?: string };
        Relationships: [];
      };
      management_report_transmissions: {
        Row: { id: string; management_report_id: string; transmission_date: string; transmission_method: ManagementReportTransmissionMethod; recipient: string; note: string | null; declared_by: string; created_at: string; updated_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      management_report_approvals: {
        Row: { id: string; management_report_id: string; approval_date: string; reviewer_name: string; reviewer_role: string | null; note: string | null; declared_by: string; created_at: string; updated_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      management_report_difficulties: {
        Row: { id: string; management_report_id: string; difficulty_date: string; recipient: string | null; reason: string; note: string | null; declared_by: string; created_at: string; updated_at: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      is_platform_admin: { Args: Record<string, never>; Returns: boolean };
      is_application_user_active: { Args: Record<string, never>; Returns: boolean };
      record_account_trial_terms_acceptance: { Args: { p_user_id: string; p_terms_version: string }; Returns: undefined };
      get_current_account_trial_state: { Args: Record<string, never>; Returns: Array<{ state: AccountTrialStateName; terms_version: string | null; terms_accepted_at: string | null; started_at: string | null; ends_at: string | null; deletion_eligible_at: string | null; remaining_days: number; active_dossier_limit: number; active_dossier_count: number; enforcement_enabled: boolean }> };
      list_administrative_account_trial_states: { Args: { p_user_ids: string[] }; Returns: Array<{ user_id: string; state: AccountTrialStateName; started_at: string | null; ends_at: string | null; deletion_eligible_at: string | null }> };
      list_administrative_account_entitlement_states: {
        Args: { p_user_ids: string[] };
        Returns: Array<{
          user_id: string;
          access_source: AccountEntitlementAccessSource;
          commercial_subscription_id: string | null;
          base_plan_key: SubscriptionPlanKey | null;
          effective_plan_key: SubscriptionPlanKey | null;
          base_active_dossier_limit: number | null;
          effective_active_dossier_limit: number | null;
          active_dossier_count: number;
          administrative_assignment_id: string | null;
          administrative_assignment_revision: number | null;
          administrative_plan_key: SubscriptionPlanKey | null;
          administrative_billing_period: AdministrativeBillingPeriod | null;
          administrative_dossier_capacity_key: AdministrativeDossierCapacityKey | null;
          administrative_override_id: string | null;
          administrative_override_revision: number | null;
          administrative_override_base_source: "commercial" | "administrative" | null;
          administrative_override_feature_plan_key: SubscriptionPlanKey | null;
          administrative_override_dossier_capacity_key: Exclude<AdministrativeDossierCapacityKey, "included"> | null;
          plan_assignment_block_code: AdministrativeEntitlementBlockCode | null;
          entitlement_override_block_code: AdministrativeEntitlementBlockCode | null;
        }>;
      };
      assign_administrative_plan: { Args: { p_owner_id: string; p_plan_key: SubscriptionPlanKey; p_billing_period: AdministrativeBillingPeriod; p_dossier_capacity_key: AdministrativeDossierCapacityKey; p_reason: string; p_request_id: string; p_expected_revision: number }; Returns: Array<{ entity_id: string; revision: number; status: string }> };
      replace_administrative_plan: { Args: { p_owner_id: string; p_assignment_id: string; p_plan_key: SubscriptionPlanKey; p_billing_period: AdministrativeBillingPeriod; p_dossier_capacity_key: AdministrativeDossierCapacityKey; p_reason: string; p_request_id: string; p_expected_revision: number }; Returns: Array<{ entity_id: string; revision: number; status: string }> };
      revoke_administrative_plan: { Args: { p_owner_id: string; p_assignment_id: string; p_reason: string; p_request_id: string; p_expected_revision: number }; Returns: Array<{ entity_id: string; revision: number; status: string }> };
      assign_administrative_entitlement_override: { Args: { p_owner_id: string; p_feature_plan_key: "comfort" | "premium" | null; p_dossier_capacity_key: "five" | "ten" | null; p_reason: string; p_request_id: string; p_expected_revision: number }; Returns: Array<{ entity_id: string; revision: number; status: string }> };
      replace_administrative_entitlement_override: { Args: { p_owner_id: string; p_override_id: string; p_feature_plan_key: "comfort" | "premium" | null; p_dossier_capacity_key: "five" | "ten" | null; p_reason: string; p_request_id: string; p_expected_revision: number }; Returns: Array<{ entity_id: string; revision: number; status: string }> };
      revoke_administrative_entitlement_override: { Args: { p_owner_id: string; p_override_id: string; p_reason: string; p_request_id: string; p_expected_revision: number }; Returns: Array<{ entity_id: string; revision: number; status: string }> };
      get_infrastructure_usage_metrics: { Args: Record<string, never>; Returns: Array<{ database_size_bytes: number; storage_size_bytes: number }> };
      check_own_email_change_availability: { Args: { p_new_email: string }; Returns: boolean };
      activate_complete_bank_reconciliation: { Args: { p_reconciliation_id: string }; Returns: Database["public"]["Tables"]["bank_reconciliations"]["Row"] };
      add_bank_reconciliation_outstanding_transaction: { Args: { p_reconciliation_id: string; p_transaction_id: string }; Returns: Database["public"]["Tables"]["bank_reconciliation_outstanding_transactions"]["Row"] };
      remove_bank_reconciliation_outstanding_transaction: { Args: { p_reconciliation_id: string; p_transaction_id: string }; Returns: undefined };
      list_bank_reconciliation_candidate_transactions: { Args: { p_reconciliation_id: string; p_after_date?: string | null; p_after_created_at?: string | null; p_after_id?: string | null; p_limit?: number }; Returns: Array<{ transaction_id: string; transaction_date: string; transaction_created_at: string; transaction_type: TransactionType; label: string; amount: number; is_outstanding: boolean; carried_from_previous: boolean }> };
      get_bank_reconciliation_detailed_summary: { Args: { p_reconciliation_id: string }; Returns: Array<{ calculated_balance: number; outstanding_debits: number; outstanding_credits: number; explained_bank_balance: number; residual_difference: number; outstanding_count: number }> };
      list_transaction_banking_impacts_for_reconciliation: { Args: { p_reconciliation_id: string }; Returns: Array<{ impact_id: string; transaction_id: string | null; impact_kind: "reverse_previous" | "apply_current"; signed_amount: number; effective_date: string; impact_created_at: string; historical_reconciliation_id: string; historical_statement_end_date: string; acknowledgement_state: "pending" | "acknowledged"; acknowledgement_id: string | null; justification: string | null; acknowledged_at: string | null }> };
      acknowledge_transaction_banking_impact: { Args: { p_reconciliation_id: string; p_impact_id: string; p_justification: string }; Returns: Json };
      review_application_user_registration: { Args: { p_user_id: string; p_decision: "active" | "rejected" }; Returns: "active" | "rejected" };
      is_protected_person_owner: { Args: { person_id: string }; Returns: boolean };
      can_read_protected_person: { Args: { person_id: string }; Returns: boolean };
      can_manage_protected_person: { Args: { person_id: string }; Returns: boolean };
      correct_property_sale_price: { Args: { p_protected_person_id: string; p_property_id: string; p_event_id: string; p_expected_price: number; p_new_price: number; p_reason: string }; Returns: string };
      correct_property_event: { Args: { p_protected_person_id: string; p_property_id: string; p_event_id: string; p_expected_revision: number; p_event_type: PropertyEventType; p_event_date: string; p_description: string; p_amount: number | null; p_document_reference: string | null; p_reason: string }; Returns: number };
      cancel_property_event: { Args: { p_protected_person_id: string; p_property_id: string; p_event_id: string; p_expected_revision: number; p_reason: string }; Returns: number };
      archive_real_estate_property: { Args: { p_protected_person_id: string; p_property_id: string; p_expected_revision: number; p_reason: string }; Returns: number };
      restore_real_estate_property: { Args: { p_protected_person_id: string; p_property_id: string; p_expected_revision: number; p_reason: string }; Returns: number };
      archive_protected_person: { Args: { p_protected_person_id: string; p_expected_revision: number; p_reason: string }; Returns: number };
      restore_protected_person: { Args: { p_protected_person_id: string; p_expected_revision: number; p_reason: string }; Returns: number };
      set_patrimony_absence_confirmation: { Args: { p_protected_person_id: string; p_category: PatrimonyAbsenceCategory; p_confirmed: boolean }; Returns: boolean };
      settle_debt: { Args: { p_protected_person_id: string; p_debt_id: string; p_expected_revision: number; p_settled_at: string; p_reason: string }; Returns: number };
      correct_debt_balance: { Args: { p_protected_person_id: string; p_debt_id: string; p_debt_balance_id: string; p_expected_revision: number; p_balance_date: string; p_remaining_balance: number; p_remaining_duration_months: number | null; p_reason: string }; Returns: number };
      cancel_debt_balance: { Args: { p_protected_person_id: string; p_debt_id: string; p_debt_balance_id: string; p_expected_revision: number; p_reason: string }; Returns: number };
      accept_protected_person_invitation: { Args: { p_token_hash: string }; Returns: string };
      decline_protected_person_invitation: { Args: { p_token_hash: string }; Returns: string };
      issue_protected_person_invitation: { Args: { p_protected_person_id: string; p_email: string; p_role: SharedAccessRole; p_token_hash: string; p_expires_at: string }; Returns: string };
      reissue_protected_person_invitation: { Args: { p_invitation_id: string; p_token_hash: string; p_expires_at: string }; Returns: string };
      revoke_protected_person_invitation: { Args: { p_invitation_id: string }; Returns: undefined };
      get_protected_person_share_capacity: { Args: { p_protected_person_id: string }; Returns: Array<{ share_role: SharedAccessRole; role_limit: number; active_access_count: number; pending_invitation_count: number; used_count: number; remaining_count: number; exceeded_by: number }> };
      change_protected_person_access_role: { Args: { p_protected_person_id: string; p_access_id: string; p_role: SharedAccessRole }; Returns: undefined };
      remove_protected_person_access: { Args: { p_protected_person_id: string; p_access_id: string }; Returns: undefined };
      create_internal_transfer: { Args: { p_protected_person_id: string; p_source_account_id: string; p_destination_account_id: string; p_transfer_date: string; p_amount: number; p_label?: string | null; p_comment?: string | null }; Returns: string };
      delete_internal_transfer: { Args: { p_transfer_id: string }; Returns: undefined };
      delete_empty_financial_account: { Args: { p_account_id: string }; Returns: undefined };
      delete_empty_protected_person: { Args: { p_protected_person_id: string }; Returns: undefined };
      delete_transaction_with_document: { Args: { p_transaction_id: string }; Returns: undefined };
      create_financial_transaction: { Args: { p_protected_person_id: string; p_financial_account_id: string; p_transaction_date: string; p_transaction_type: "income" | "expense"; p_label: string; p_amount: number; p_category_id: string | null; p_official_category_id: string | null; p_classification_precision: string | null; p_comment: string | null; p_request_id: string }; Returns: Json };
      correct_financial_transaction: { Args: { p_protected_person_id: string; p_transaction_id: string; p_expected_revision: number; p_financial_account_id: string; p_transaction_date: string; p_transaction_type: "income" | "expense"; p_label: string; p_amount: number; p_category_id: string | null; p_official_category_id: string | null; p_classification_precision: string | null; p_comment: string | null; p_reason: string; p_request_id: string }; Returns: Json };
      cancel_financial_transaction: { Args: { p_protected_person_id: string; p_transaction_id: string; p_expected_revision: number; p_reason: string; p_request_id: string }; Returns: Json };
      create_internal_transfer_v2: { Args: { p_protected_person_id: string; p_source_account_id: string; p_destination_account_id: string; p_transfer_date: string; p_amount: number; p_label: string | null; p_comment: string | null; p_request_id: string }; Returns: Json };
      correct_internal_transfer: { Args: { p_protected_person_id: string; p_transfer_id: string; p_expected_revision: number; p_source_account_id: string; p_destination_account_id: string; p_transfer_date: string; p_amount: number; p_label: string | null; p_comment: string | null; p_reason: string; p_request_id: string }; Returns: Json };
      cancel_internal_transfer_v2: { Args: { p_protected_person_id: string; p_transfer_id: string; p_expected_revision: number; p_reason: string; p_request_id: string }; Returns: Json };
      reserve_transaction_proof_version: { Args: { p_protected_person_id: string; p_transaction_id: string; p_intent: "create" | "replace"; p_client_request_id: string }; Returns: Json };
      finalize_transaction_proof_version: { Args: { p_operation_id: string; p_expected_operation_revision: number; p_file_name: string; p_mime_type: string; p_file_size: number; p_sha256: string; p_storage_object_id: string }; Returns: Json };
      finalize_management_report_draft_generation: { Args: { p_report_id: string; p_storage_path: string; p_file_name: string; p_mime_type: string; p_file_size: number; p_preview_snapshot: Json; p_snapshot_schema_version: number }; Returns: string };
      resume_management_report_preparation: { Args: { p_report_id: string }; Returns: undefined };
      finalize_management_report: { Args: { p_report_id: string; p_storage_path: string; p_file_name: string; p_mime_type: string; p_file_size: number; p_preview_snapshot: Json; p_snapshot_schema_version: number }; Returns: string };
      declare_management_report_transmission: { Args: { p_report_id: string; p_transmission_date: string; p_transmission_method: string; p_recipient: string; p_note?: string | null }; Returns: string };
      declare_management_report_approval: { Args: { p_report_id: string; p_approval_date: string; p_reviewer_name: string; p_reviewer_role?: string | null; p_note?: string | null }; Returns: string };
      declare_management_report_difficulty: { Args: { p_report_id: string; p_difficulty_date: string; p_reason: string; p_recipient?: string | null; p_note?: string | null }; Returns: string };
      list_current_user_owned_storage_objects: { Args: Record<string, never>; Returns: Array<{ bucket_id: string; name: string; metadata: Json; user_metadata: Json }> };
      issue_account_deletion_document_authorization: { Args: { p_account_user_id: string; p_attempt_id: string }; Returns: Json };
      cancel_account_deletion_document_authorization: { Args: { p_authorization_id: string }; Returns: Json };
      begin_account_storage_neutralization: { Args: { p_authorization_id: string; p_client_request_id: string; p_bucket_id: string; p_object_path: string; p_expected_object_id: string; p_expected_object_version: string; p_expected_sha256: string; p_expected_byte_size: number; p_mime_type: string }; Returns: Json };
      reserve_account_storage_neutralization_backup: { Args: { p_operation_id: string }; Returns: Json };
      confirm_account_storage_neutralization_backup: { Args: { p_operation_id: string; p_expected_neutralization_revision: number; p_expected_backup_revision: number; p_observed_sha256: string; p_observed_byte_size: number }; Returns: Json };
      record_account_storage_neutralization_original_deleted: { Args: { p_operation_id: string; p_expected_revision: number }; Returns: Json };
      authorize_account_storage_neutralization_recovery: { Args: { p_operation_id: string; p_expected_revision: number }; Returns: Json };
      confirm_account_storage_neutralization_recovery: { Args: { p_operation_id: string; p_expected_revision: number; p_observed_object_id: string; p_observed_object_version: string; p_observed_sha256: string; p_observed_byte_size: number }; Returns: Json };
      verify_account_storage_neutralization_content: { Args: { p_operation_id: string; p_expected_revision: number; p_observed_sha256: string; p_observed_byte_size: number }; Returns: Json };
      authorize_account_storage_neutralization_backup_cleanup: { Args: { p_operation_id: string; p_expected_revision: number }; Returns: Json };
      confirm_account_storage_neutralization_backup_cleanup: { Args: { p_operation_id: string; p_expected_neutralization_revision: number; p_expected_backup_revision: number }; Returns: Json };
      finalize_account_storage_neutralization: { Args: { p_operation_id: string; p_expected_revision: number }; Returns: Json };
      mark_account_storage_neutralization_attention_required: { Args: { p_operation_id: string; p_expected_revision: number; p_safe_error_code: string }; Returns: Json };
      get_account_storage_neutralization_progress: { Args: { p_operation_id: string }; Returns: Json };
      assert_account_deletion_document_barrier: { Args: { p_authorization_id: string }; Returns: Json };
      list_account_storage_neutralization_operations: { Args: { p_account_user_id: string }; Returns: Array<{ operation_id: string; client_request_id: string; state: string; phase: string; created_at: string }> };
      get_administrative_account_deletion_diagnostic: { Args: { p_target_user_id: string }; Returns: Json };
      get_administrative_account_deletion_attempt: { Args: { p_target_user_id: string; p_attempt_id: string }; Returns: Json };
      issue_administrative_account_deletion_authorization: { Args: { p_target_user_id: string; p_attempt_id: string; p_reason: string; p_document_plan: Json }; Returns: Json };
      cancel_administrative_account_deletion_authorization: { Args: { p_authorization_id: string; p_expected_revision: number }; Returns: Json };
      begin_administrative_account_storage_neutralization: { Args: { p_authorization_id: string; p_client_request_id: string; p_bucket_id: string; p_object_path: string; p_expected_object_id: string; p_expected_object_version: string; p_expected_sha256: string; p_expected_byte_size: number; p_mime_type: string }; Returns: Json };
      list_administrative_account_storage_neutralization_operations: { Args: { p_authorization_id: string }; Returns: Array<{ operation_id: string; client_request_id: string; state: string; phase: string; created_at: string }> };
      assert_administrative_account_deletion_barrier: { Args: { p_authorization_id: string; p_expected_revision: number; p_expected_plan_hash: string }; Returns: Json };
      get_administrative_document_inventory: { Args: { p_limit?: number; p_after_key?: string | null; p_document_category?: string | null; p_anomaly_type?: string | null }; Returns: Json };
      begin_administrative_document_physical_verification: { Args: { p_inventory_key: string; p_client_request_id: string }; Returns: Json };
      get_administrative_document_physical_verification_descriptor: { Args: { p_verification_request_id: string }; Returns: Json };
      complete_administrative_document_physical_verification: { Args: { p_verification_request_id: string; p_server_capability: string; p_outcome: string; p_proof_level: string; p_catalog_object_id: string | null; p_catalog_object_version: string | null; p_observed_byte_size: number | null; p_observed_sha256: string | null; p_limitation_code: string | null }; Returns: Json };
      get_administrative_document_physical_observations: { Args: { p_inventory_key: string; p_limit?: number; p_before_observed_at?: string | null }; Returns: Json };
      get_administrative_document_repair_capabilities: { Args: Record<string, never>; Returns: Json };
      request_administrative_document_exceptional_recovery: { Args: { p_authorization_id: string; p_attempt_id: string; p_expected_plan_hash: string; p_request_id: string; p_reason: string; p_expected_authorization_revision: number }; Returns: Json };
      decide_administrative_document_exceptional_recovery: { Args: { p_recovery_id: string; p_decision_id: string; p_approve: boolean; p_reason: string; p_expected_revision: number }; Returns: Json };
      activate_administrative_document_exceptional_recovery: { Args: { p_recovery_id: string; p_activation_id: string; p_expected_revision: number }; Returns: Json };
      get_administrative_document_exceptional_recovery: { Args: { p_recovery_id: string }; Returns: Json };
      get_administrative_document_exceptional_recovery_for_operation: { Args: { p_operation_id: string }; Returns: Json };
      list_pending_administrative_document_exceptional_recoveries: { Args: { p_limit?: number; p_after_requested_at?: string | null; p_after_id?: string | null }; Returns: Json };
      validate_bank_reconciliation: { Args: { p_reconciliation_id: string }; Returns: Database["public"]["Tables"]["bank_reconciliations"]["Row"] };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

export type ProtectedPerson = Database["public"]["Tables"]["protected_persons"]["Row"];
export type ProtectionMeasure = Database["public"]["Tables"]["protection_measures"]["Row"];
export type ManagementPeriod = Database["public"]["Tables"]["management_periods"]["Row"];
export type FinancialAccount = Database["public"]["Tables"]["financial_accounts"]["Row"];
export type AccountValuation = Database["public"]["Tables"]["account_valuations"]["Row"];
export type Category = Database["public"]["Tables"]["categories"]["Row"];
export type Transaction = Database["public"]["Tables"]["transactions"]["Row"];
export type TransactionDocument = Database["public"]["Tables"]["transaction_documents"]["Row"];
export type TransactionChange = Database["public"]["Tables"]["transaction_changes"]["Row"];
export type TransactionDocumentHistory = Database["public"]["Tables"]["transaction_document_history"]["Row"];
export type TransactionProofDocument = Database["public"]["Tables"]["transaction_proof_documents"]["Row"];
export type TransactionProofVersion = Database["public"]["Tables"]["transaction_proof_versions"]["Row"];
export type TransactionProofReplacementRetirement = Database["public"]["Tables"]["transaction_proof_replacement_retirements"]["Row"];
export type Transfer = Database["public"]["Tables"]["transfers"]["Row"];
export type TransferChange = Database["public"]["Tables"]["transfer_changes"]["Row"];
export type AccountRequest = Database["public"]["Tables"]["account_requests"]["Row"];
export type ProtectedPersonAccess = Database["public"]["Tables"]["protected_person_access"]["Row"];
export type ProtectedPersonInvitation = Database["public"]["Tables"]["protected_person_invitations"]["Row"];
export type ProtectedPersonArchiveChange = Database["public"]["Tables"]["protected_person_archive_changes"]["Row"];
export type RealEstateProperty = Database["public"]["Tables"]["real_estate_properties"]["Row"];
export type PropertyEvent = Database["public"]["Tables"]["property_events"]["Row"];
export type PropertyEventChange = Database["public"]["Tables"]["property_event_changes"]["Row"];
export type PropertyArchiveChange = Database["public"]["Tables"]["property_archive_changes"]["Row"];
export type PropertySalePriceCorrection = Database["public"]["Tables"]["property_sale_price_corrections"]["Row"];
export type PatrimonyAbsenceConfirmation = Database["public"]["Tables"]["patrimony_absence_confirmations"]["Row"];
export type Debt = Database["public"]["Tables"]["debts"]["Row"];
export type DebtBalance = Database["public"]["Tables"]["debt_balances"]["Row"];
export type DebtBalanceChange = Database["public"]["Tables"]["debt_balance_changes"]["Row"];
export type DebtStatusChange = Database["public"]["Tables"]["debt_status_changes"]["Row"];
export type BankStatement = Database["public"]["Tables"]["bank_statements"]["Row"];
export type BankReconciliation = Database["public"]["Tables"]["bank_reconciliations"]["Row"];
export type BankReconciliationOutstandingTransaction = Database["public"]["Tables"]["bank_reconciliation_outstanding_transactions"]["Row"];
export type ManagementReport = Database["public"]["Tables"]["management_reports"]["Row"];
export type ManagementReportDocument = Database["public"]["Tables"]["management_report_documents"]["Row"];
export type ManagementReportAccountSelection = Database["public"]["Tables"]["management_report_account_selections"]["Row"];
export type ManagementReportTransmission = Database["public"]["Tables"]["management_report_transmissions"]["Row"];
export type ManagementReportApproval = Database["public"]["Tables"]["management_report_approvals"]["Row"];
export type ManagementReportDifficulty = Database["public"]["Tables"]["management_report_difficulties"]["Row"];
