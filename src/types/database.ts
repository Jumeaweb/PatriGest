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
export type PropertyType = "house" | "apartment" | "land" | "commercial" | "other";
export type PropertyEntryMode = "acquisition" | "inheritance" | "donation" | "other";
export type PropertyStatus = "active" | "disposed";
export type PropertyEventType = "acquisition" | "sale" | "inheritance" | "donation" | "significant_change";
export type DebtType = "bank_loan" | "tax_debt" | "institution_debt" | "personal_debt" | "other";
export type DebtStatus = "active" | "settled";
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
        Row: { user_id: string; status: ApplicationUserAuthorizationStatus; status_changed_at: string; status_changed_by: string | null; created_at: string; updated_at: string };
        Insert: { user_id: string; status?: ApplicationUserAuthorizationStatus; status_changed_at?: string; status_changed_by?: string | null; created_at?: string; updated_at?: string };
        Update: { status?: ApplicationUserAuthorizationStatus; status_changed_at?: string; status_changed_by?: string | null; updated_at?: string };
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
          updated_at: string; archived_at: string | null;
        };
        Insert: {
          id?: string; owner_id: string; first_name: string; last_name: string;
          birth_name?: string | null; birth_date?: string | null; birth_place?: string | null;
          address_line1?: string | null; address_line2?: string | null; postal_code?: string | null;
          city?: string | null; country?: string; phone?: string | null; email?: string | null;
          residence_address_line1?: string | null; residence_address_line2?: string | null;
          residence_postal_code?: string | null; residence_city?: string | null; residence_country?: string | null;
          notes?: string | null; status?: ProtectedPersonStatus; created_at?: string;
          updated_at?: string; archived_at?: string | null;
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
        Row: { id: string; protected_person_id: string; email: string; role: SharedAccessRole; token_hash: string; expires_at: string; accepted_at: string | null; revoked_at: string | null; invited_by: string | null; created_at: string };
        Insert: { id?: string; protected_person_id: string; email: string; role: SharedAccessRole; token_hash: string; expires_at: string; accepted_at?: string | null; revoked_at?: string | null; invited_by: string | null; created_at?: string };
        Update: { role?: SharedAccessRole; expires_at?: string; accepted_at?: string | null; revoked_at?: string | null };
        Relationships: [];
      };
      categories: {
        Row: { id: string; owner_id: string | null; name: string; usage: CategoryUsage; is_system: boolean; active: boolean; official_code: string | null; official_section: string | null; official_group: string | null; official_order: number | null; official_category_id: string | null; requires_precision: boolean; created_at: string; updated_at: string };
        Insert: { id?: string; owner_id?: string | null; name: string; usage: CategoryUsage; is_system?: boolean; active?: boolean; official_code?: string | null; official_section?: string | null; official_group?: string | null; official_order?: number | null; official_category_id?: string | null; created_at?: string; updated_at?: string };
        Update: { name?: string; usage?: CategoryUsage; active?: boolean; official_category_id?: string | null; updated_at?: string };
        Relationships: [{ foreignKeyName: "categories_official_category_id_fkey"; columns: ["official_category_id"]; isOneToOne: false; referencedRelation: "categories"; referencedColumns: ["id"] }];
      };
      transfers: {
        Row: { id: string; protected_person_id: string; source_account_id: string; destination_account_id: string; transfer_date: string; amount: number; label: string | null; comment: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; source_account_id: string; destination_account_id: string; transfer_date: string; amount: number; label?: string | null; comment?: string | null; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["transfers"]["Insert"]>;
        Relationships: [];
      };
      transactions: {
        Row: { id: string; financial_account_id: string; transaction_date: string; transaction_type: TransactionType; label: string; amount: number; category_id: string | null; transfer_id: string | null; proof_reference: string | null; comment: string | null; accounting_nature: AccountingNature | null; official_category_id: string | null; classification_precision: string | null; created_at: string; updated_at: string };
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
        Row: { transaction_id: string; protected_person_id: string; reference_year: number; reference_number: number; proof_reference: string; created_at: string };
        Insert: { transaction_id: string; protected_person_id: string; reference_year: number; reference_number: number; proof_reference: string; created_at?: string };
        Update: never;
        Relationships: [];
      };
      transaction_documents: {
        Row: { id: string; transaction_id: string; storage_path: string; file_name: string; mime_type: string; file_size: number; created_by: string; created_at: string; updated_at: string };
        Insert: { id?: string; transaction_id: string; storage_path: string; file_name: string; mime_type: string; file_size: number; created_by: string; created_at?: string; updated_at?: string };
        Update: { file_name?: string; mime_type?: string; file_size?: number; created_by?: string; updated_at?: string };
        Relationships: [];
      };
      real_estate_properties: {
        Row: { id: string; protected_person_id: string; property_type: PropertyType; designation: string; address_line1: string | null; address_line2: string | null; postal_code: string | null; city: string | null; country: string; entry_date: string | null; entry_mode: PropertyEntryMode | null; estimated_value: number | null; valuation_date: string | null; status: PropertyStatus; disposal_date: string | null; notes: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; property_type: PropertyType; designation: string; address_line1?: string | null; address_line2?: string | null; postal_code?: string | null; city?: string | null; country?: string; entry_date?: string | null; entry_mode?: PropertyEntryMode | null; estimated_value?: number | null; valuation_date?: string | null; status?: PropertyStatus; disposal_date?: string | null; notes?: string | null; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["real_estate_properties"]["Insert"]>;
        Relationships: [];
      };
      property_events: {
        Row: { id: string; property_id: string; protected_person_id: string; event_type: PropertyEventType; event_date: string; description: string; amount: number | null; document_reference: string | null; created_at: string };
        Insert: { id?: string; property_id: string; protected_person_id: string; event_type: PropertyEventType; event_date: string; description: string; amount?: number | null; document_reference?: string | null; created_at?: string };
        Update: Partial<Database["public"]["Tables"]["property_events"]["Insert"]>;
        Relationships: [];
      };
      debts: {
        Row: { id: string; protected_person_id: string; creditor: string; debt_type: DebtType; designation: string; start_date: string | null; initial_amount: number | null; initial_duration_months: number | null; monthly_payment: number | null; interest_rate: number | null; current_balance: number | null; current_balance_date: string | null; remaining_duration_months: number | null; status: DebtStatus; settled_at: string | null; notes: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; creditor: string; debt_type: DebtType; designation: string; start_date?: string | null; initial_amount?: number | null; initial_duration_months?: number | null; monthly_payment?: number | null; interest_rate?: number | null; current_balance?: number | null; current_balance_date?: string | null; remaining_duration_months?: number | null; status?: DebtStatus; settled_at?: string | null; notes?: string | null; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["debts"]["Insert"]>;
        Relationships: [];
      };
      debt_balances: {
        Row: { id: string; debt_id: string; balance_date: string; remaining_balance: number; remaining_duration_months: number | null; created_at: string };
        Insert: { id?: string; debt_id: string; balance_date: string; remaining_balance: number; remaining_duration_months?: number | null; created_at?: string };
        Update: Partial<Database["public"]["Tables"]["debt_balances"]["Insert"]>;
        Relationships: [];
      };
      bank_statements: {
        Row: { id: string; financial_account_id: string; statement_start_date: string | null; statement_end_date: string; statement_balance: number | null; storage_path: string; original_file_name: string | null; mime_type: string | null; file_size: number | null; note: string | null; created_by: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; financial_account_id: string; statement_start_date?: string | null; statement_end_date: string; statement_balance?: number | null; storage_path: string; original_file_name?: string | null; mime_type?: string | null; file_size?: number | null; note?: string | null; created_by: string; created_at?: string; updated_at?: string };
        Update: { statement_start_date?: string | null; statement_end_date?: string; statement_balance?: number | null; original_file_name?: string | null; mime_type?: string | null; file_size?: number | null; note?: string | null; updated_at?: string };
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
      management_reports: {
        Row: { id: string; protected_person_id: string; management_period_id: string | null; report_year: number; period_start: string; period_end: string; status: ManagementReportStatus; residence_changed: boolean | null; representative_address_changed: boolean | null; real_estate_confirmed: boolean | null; financial_investments_confirmed: boolean | null; observations: string | null; signature_place: string | null; generated_at: string | null; finalized_at: string | null; transmitted_at: string | null; approved_at: string | null; difficulty_reported_at: string | null; created_by: string; created_at: string; updated_at: string };
        Insert: { id?: string; protected_person_id: string; management_period_id?: string | null; report_year: number; period_start: string; period_end: string; status?: ManagementReportStatus; residence_changed?: boolean | null; representative_address_changed?: boolean | null; real_estate_confirmed?: boolean | null; financial_investments_confirmed?: boolean | null; observations?: string | null; signature_place?: string | null; generated_at?: string | null; finalized_at?: string | null; transmitted_at?: string | null; approved_at?: string | null; difficulty_reported_at?: string | null; created_by: string; created_at?: string; updated_at?: string };
        Update: { status?: ManagementReportStatus; residence_changed?: boolean | null; representative_address_changed?: boolean | null; real_estate_confirmed?: boolean | null; financial_investments_confirmed?: boolean | null; observations?: string | null; signature_place?: string | null; generated_at?: string | null; finalized_at?: string | null; transmitted_at?: string | null; approved_at?: string | null; difficulty_reported_at?: string | null; updated_at?: string };
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
      activate_complete_bank_reconciliation: { Args: { p_reconciliation_id: string }; Returns: Database["public"]["Tables"]["bank_reconciliations"]["Row"] };
      add_bank_reconciliation_outstanding_transaction: { Args: { p_reconciliation_id: string; p_transaction_id: string }; Returns: Database["public"]["Tables"]["bank_reconciliation_outstanding_transactions"]["Row"] };
      remove_bank_reconciliation_outstanding_transaction: { Args: { p_reconciliation_id: string; p_transaction_id: string }; Returns: undefined };
      list_bank_reconciliation_candidate_transactions: { Args: { p_reconciliation_id: string; p_after_date?: string | null; p_after_created_at?: string | null; p_after_id?: string | null; p_limit?: number }; Returns: Array<{ transaction_id: string; transaction_date: string; transaction_created_at: string; transaction_type: TransactionType; label: string; amount: number; is_outstanding: boolean; carried_from_previous: boolean }> };
      get_bank_reconciliation_detailed_summary: { Args: { p_reconciliation_id: string }; Returns: Array<{ calculated_balance: number; outstanding_debits: number; outstanding_credits: number; explained_bank_balance: number; residual_difference: number; outstanding_count: number }> };
      review_application_user_registration: { Args: { p_user_id: string; p_decision: "active" | "rejected" }; Returns: "active" | "rejected" };
      is_protected_person_owner: { Args: { person_id: string }; Returns: boolean };
      can_read_protected_person: { Args: { person_id: string }; Returns: boolean };
      can_manage_protected_person: { Args: { person_id: string }; Returns: boolean };
      accept_protected_person_invitation: { Args: { p_token_hash: string }; Returns: string };
      issue_protected_person_invitation: { Args: { p_protected_person_id: string; p_email: string; p_role: SharedAccessRole; p_token_hash: string; p_expires_at: string }; Returns: string };
      reissue_protected_person_invitation: { Args: { p_invitation_id: string; p_token_hash: string; p_expires_at: string }; Returns: string };
      revoke_protected_person_invitation: { Args: { p_invitation_id: string }; Returns: undefined };
      remove_protected_person_access: { Args: { p_protected_person_id: string; p_access_id: string }; Returns: undefined };
      create_internal_transfer: { Args: { p_protected_person_id: string; p_source_account_id: string; p_destination_account_id: string; p_transfer_date: string; p_amount: number; p_label?: string | null; p_comment?: string | null }; Returns: string };
      delete_internal_transfer: { Args: { p_transfer_id: string }; Returns: undefined };
      delete_empty_financial_account: { Args: { p_account_id: string }; Returns: undefined };
      delete_empty_protected_person: { Args: { p_protected_person_id: string }; Returns: undefined };
      delete_transaction_with_document: { Args: { p_transaction_id: string }; Returns: undefined };
      finalize_management_report_draft_generation: { Args: { p_report_id: string; p_storage_path: string; p_file_name: string; p_mime_type: string; p_file_size: number; p_preview_snapshot: Json; p_snapshot_schema_version: number }; Returns: string };
      resume_management_report_preparation: { Args: { p_report_id: string }; Returns: undefined };
      finalize_management_report: { Args: { p_report_id: string; p_storage_path: string; p_file_name: string; p_mime_type: string; p_file_size: number; p_preview_snapshot: Json; p_snapshot_schema_version: number }; Returns: string };
      declare_management_report_transmission: { Args: { p_report_id: string; p_transmission_date: string; p_transmission_method: string; p_recipient: string; p_note?: string | null }; Returns: string };
      declare_management_report_approval: { Args: { p_report_id: string; p_approval_date: string; p_reviewer_name: string; p_reviewer_role?: string | null; p_note?: string | null }; Returns: string };
      declare_management_report_difficulty: { Args: { p_report_id: string; p_difficulty_date: string; p_reason: string; p_recipient?: string | null; p_note?: string | null }; Returns: string };
      list_current_user_owned_storage_objects: { Args: Record<string, never>; Returns: Array<{ bucket_id: string; name: string; metadata: Json; user_metadata: Json }> };
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
export type Transfer = Database["public"]["Tables"]["transfers"]["Row"];
export type AccountRequest = Database["public"]["Tables"]["account_requests"]["Row"];
export type ProtectedPersonAccess = Database["public"]["Tables"]["protected_person_access"]["Row"];
export type ProtectedPersonInvitation = Database["public"]["Tables"]["protected_person_invitations"]["Row"];
export type RealEstateProperty = Database["public"]["Tables"]["real_estate_properties"]["Row"];
export type PropertyEvent = Database["public"]["Tables"]["property_events"]["Row"];
export type Debt = Database["public"]["Tables"]["debts"]["Row"];
export type DebtBalance = Database["public"]["Tables"]["debt_balances"]["Row"];
export type BankStatement = Database["public"]["Tables"]["bank_statements"]["Row"];
export type BankReconciliation = Database["public"]["Tables"]["bank_reconciliations"]["Row"];
export type BankReconciliationOutstandingTransaction = Database["public"]["Tables"]["bank_reconciliation_outstanding_transactions"]["Row"];
export type ManagementReport = Database["public"]["Tables"]["management_reports"]["Row"];
export type ManagementReportDocument = Database["public"]["Tables"]["management_report_documents"]["Row"];
export type ManagementReportAccountSelection = Database["public"]["Tables"]["management_report_account_selections"]["Row"];
export type ManagementReportTransmission = Database["public"]["Tables"]["management_report_transmissions"]["Row"];
export type ManagementReportApproval = Database["public"]["Tables"]["management_report_approvals"]["Row"];
export type ManagementReportDifficulty = Database["public"]["Tables"]["management_report_difficulties"]["Row"];
