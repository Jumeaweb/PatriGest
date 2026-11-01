import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { DebtBalanceCancellationInput, DebtBalanceCorrectionInput, DebtBalanceInput, DebtInput, DebtSettlementInput, PatrimonyAbsenceConfirmationInput, PropertyArchiveChangeInput, PropertyEventCancellationInput, PropertyEventCorrectionInput, PropertyEventInput, PropertyInput, PropertySalePriceCorrectionInput } from "./schemas";
import { buildPatrimonyAbsenceConfirmationState, type PatrimonyAbsenceConfirmationState } from "./patrimony-absence";

export type PropertyEventCorrectionErrorCode = "forbidden" | "not_found" | "stale_revision" | "invalid" | "closed_period" | "incompatible_transition" | "ambiguous_entry" | "inconsistent" | "sale_price" | "technical";
export class PropertyEventCorrectionError extends Error {
  constructor(readonly code: PropertyEventCorrectionErrorCode) { super(code); this.name = "PropertyEventCorrectionError"; }
}
export type PropertySalePriceCorrectionErrorCode = "forbidden" | "not_found" | "stale_price" | "invalid" | "closed_period" | "inconsistent" | "technical";
export class PropertySalePriceCorrectionError extends Error {
  constructor(readonly code: PropertySalePriceCorrectionErrorCode) { super(code); this.name = "PropertySalePriceCorrectionError"; }
}
export type PropertyEventCancellationErrorCode = "forbidden" | "not_found" | "stale_revision" | "invalid" | "already_cancelled" | "closed_period" | "entry_event" | "inconsistent" | "technical";
export class PropertyEventCancellationError extends Error {
  constructor(readonly code: PropertyEventCancellationErrorCode) { super(code); this.name = "PropertyEventCancellationError"; }
}
export type PropertyArchiveChangeErrorCode = "forbidden" | "not_found" | "stale_revision" | "invalid" | "already_archived" | "not_archived" | "inconsistent" | "technical";
export class PropertyArchiveChangeError extends Error {
  constructor(readonly code: PropertyArchiveChangeErrorCode) { super(code); this.name = "PropertyArchiveChangeError"; }
}
export type PatrimonyAbsenceConfirmationErrorCode = "forbidden" | "invalid" | "technical";
export class PatrimonyAbsenceConfirmationError extends Error {
  constructor(readonly code: PatrimonyAbsenceConfirmationErrorCode) { super(code); this.name = "PatrimonyAbsenceConfirmationError"; }
}
export type DebtSettlementErrorCode = "forbidden" | "not_found" | "stale_revision" | "already_settled" | "positive_balance" | "missing_zero_balance" | "later_balance" | "missing_start_date" | "invalid_date" | "closed_period" | "archived_dossier" | "inconsistent" | "invalid" | "technical";
export class DebtSettlementError extends Error {
  constructor(readonly code: DebtSettlementErrorCode) { super(code); this.name = "DebtSettlementError"; }
}
export type DebtBalanceErrorCode = "forbidden" | "not_found" | "stale_revision" | "already_cancelled" | "settled" | "closed_period" | "duplicate_date" | "archived_dossier" | "invalid" | "technical";
export class DebtBalanceError extends Error {
  constructor(readonly code: DebtBalanceErrorCode) { super(code); this.name = "DebtBalanceError"; }
}
function mapDebtBalanceError(error: { code?: string; message: string }): DebtBalanceError {
  const message = error.message.toLocaleLowerCase("fr-FR");
  if (error.code === "42501") return new DebtBalanceError("forbidden");
  if (error.code === "P0002") return new DebtBalanceError("not_found");
  if (error.code === "40001") return new DebtBalanceError("stale_revision");
  if (error.code === "P4R01" || message.includes("dossier") && message.includes("archive")) return new DebtBalanceError("archived_dossier");
  if (error.code === "23505" || message.includes("date") && (message.includes("existe") || message.includes("utilisee"))) return new DebtBalanceError("duplicate_date");
  if (message.includes("exercice cloture") || message.includes("exercice clôturé")) return new DebtBalanceError("closed_period");
  if (message.includes("deja annulee") || message.includes("déjà annulée") || message.includes("annulee ne peut")) return new DebtBalanceError("already_cancelled");
  if (message.includes("dette soldee") || message.includes("dette soldée")) return new DebtBalanceError("settled");
  if (error.code === "23514" || error.code === "22003") return new DebtBalanceError("invalid");
  return new DebtBalanceError("technical");
}
const PROPERTY_EVENT_CLOSED_PERIOD_MESSAGE = "Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l’assistance PatriGest.";
export async function getProperties(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("protected_person_id",personId).is("archived_at",null).order("status").order("designation");if(error)throw new Error("Impossible de charger le patrimoine immobilier.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("property_events").select("*").in("property_id",ids).is("cancelled_at",null).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger l’historique immobilier.");return data.map(property=>({...property,events:result.data.filter(event=>event.property_id===property.id)}));}
export async function getArchivedProperties(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("protected_person_id",personId).not("archived_at","is",null).order("archived_at",{ascending:false}).order("designation");if(error)throw new Error("Impossible de charger les biens archivés.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("property_events").select("*").in("property_id",ids).is("cancelled_at",null).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger l’historique immobilier.");return data.map(property=>({...property,events:result.data.filter(event=>event.property_id===property.id)}));}
export async function getProperty(personId:string,propertyId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("id",propertyId).eq("protected_person_id",personId).maybeSingle();if(error)throw new Error("Impossible de charger le bien immobilier.");if(!data)return null;const [eventsResult,archiveChangesResult]=await Promise.all([supabase.from("property_events").select("*").eq("property_id",propertyId).eq("protected_person_id",personId).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false}),supabase.from("property_archive_changes").select("*").eq("property_id",propertyId).eq("protected_person_id",personId).order("changed_at",{ascending:true}).order("id",{ascending:true})]);if(eventsResult.error)throw new Error("Impossible de charger l’historique immobilier.");if(archiveChangesResult.error)throw new Error("Impossible de charger l’historique d’archivage.");const eventIds=eventsResult.data.map(event=>event.id);const [correctionsResult,changesResult]=eventIds.length?await Promise.all([supabase.from("property_sale_price_corrections").select("*").in("property_event_id",eventIds).order("corrected_at",{ascending:true}).order("id",{ascending:true}),supabase.from("property_event_changes").select("*").in("property_event_id",eventIds).order("changed_at",{ascending:true}).order("id",{ascending:true})]):[{data:[],error:null},{data:[],error:null}];if(correctionsResult.error)throw new Error("Impossible de charger les corrections de prix de vente.");if(changesResult.error)throw new Error("Impossible de charger les corrections d’événements.");return{...data,archiveChanges:archiveChangesResult.data,events:eventsResult.data.map(event=>({...event,priceCorrections:correctionsResult.data.filter(correction=>correction.property_event_id===event.id),changes:changesResult.data.filter(change=>change.property_event_id===event.id)}))};}
export async function saveProperty(personId:string,input:PropertyInput,id?:string){const{supabase}=await getAuthenticatedUser();const payload={property_type:input.propertyType,designation:input.designation,address_line1:input.addressLine1,address_line2:input.addressLine2,postal_code:input.postalCode,city:input.city,country:input.country,entry_date:input.entryDate,entry_mode:input.entryMode,estimated_value:input.estimatedValue,valuation_date:input.valuationDate,status:input.status,disposal_date:input.disposalDate,notes:input.notes};const query=id?supabase.from("real_estate_properties").update(payload).eq("id",id).eq("protected_person_id",personId):supabase.from("real_estate_properties").insert({...payload,protected_person_id:personId});const{error}=await query.select("id").single();if(error)throw new Error("Impossible d’enregistrer le bien immobilier.");}
export async function addPropertyEvent(personId:string,propertyId:string,input:PropertyEventInput){const{supabase}=await getAuthenticatedUser();const{error}=await supabase.from("property_events").insert({property_id:propertyId,protected_person_id:personId,event_type:input.eventType,event_date:input.eventDate,description:input.description,amount:input.amount,document_reference:input.documentReference});if(error?.message.includes("Cet événement appartient à un exercice clôturé."))throw new Error(PROPERTY_EVENT_CLOSED_PERIOD_MESSAGE);if(error)throw new Error("Impossible d’enregistrer l’événement immobilier.");}
export async function correctPropertyEvent(personId:string,propertyId:string,eventId:string,expectedRevision:number,input:PropertyEventCorrectionInput){
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new PropertyEventCorrectionError("forbidden");
    throw new PropertyEventCorrectionError("technical");
  }
  const { error } = await auth.supabase.rpc("correct_property_event", {p_protected_person_id:personId,p_property_id:propertyId,p_event_id:eventId,p_expected_revision:expectedRevision,p_event_type:input.eventType,p_event_date:input.eventDate,p_description:input.description,p_amount:input.amount,p_document_reference:input.documentReference,p_reason:input.reason});
  if (!error) return;
  if (error.code === "42501") throw new PropertyEventCorrectionError("forbidden");
  if (error.code === "P0002") throw new PropertyEventCorrectionError("not_found");
  if (error.code === "40001") throw new PropertyEventCorrectionError("stale_revision");
  if (error.message.includes("Cet événement appartient à un exercice clôturé.")) throw new PropertyEventCorrectionError("closed_period");
  if (error.message === "Cette transition de type d’événement n’est pas autorisée.") throw new PropertyEventCorrectionError("incompatible_transition");
  if (error.message.includes("Plusieurs événements d’entrée")) throw new PropertyEventCorrectionError("ambiguous_entry");
  if (["La fiche du bien et son événement d’entrée sont incohérents.","Le bien et son événement de vente sont incohérents.","Plusieurs ventes historiques empêchent la correction de l’entrée.","La correction exige une unique vente pour ce bien."].includes(error.message)) throw new PropertyEventCorrectionError("inconsistent");
  if (error.message === "Le prix de vente doit être corrigé par le parcours dédié.") throw new PropertyEventCorrectionError("sale_price");
  if (error.code === "23514") throw new PropertyEventCorrectionError("invalid");
  throw new PropertyEventCorrectionError("technical");
}
export async function correctPropertySalePrice(personId:string,propertyId:string,eventId:string,input:PropertySalePriceCorrectionInput){
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new PropertySalePriceCorrectionError("forbidden");
    throw new PropertySalePriceCorrectionError("technical");
  }
  const { error } = await auth.supabase.rpc("correct_property_sale_price", {
    p_protected_person_id: personId,
    p_property_id: propertyId,
    p_event_id: eventId,
    p_expected_price: input.expectedPrice,
    p_new_price: input.newPrice,
    p_reason: input.reason,
  });
  if (!error) return;
  if (error.code === "42501") throw new PropertySalePriceCorrectionError("forbidden");
  if (error.code === "P0002") throw new PropertySalePriceCorrectionError("not_found");
  if (error.code === "40001") throw new PropertySalePriceCorrectionError("stale_price");
  if (error.code === "23514") throw new PropertySalePriceCorrectionError("invalid");
  if (error.message === "Cette vente appartient à un exercice clôturé.") throw new PropertySalePriceCorrectionError("closed_period");
  if (["La correction exige une unique vente pour ce bien.", "Le bien et son événement de vente sont incohérents."].includes(error.message)) throw new PropertySalePriceCorrectionError("inconsistent");
  throw new PropertySalePriceCorrectionError("technical");
}
export async function cancelPropertyEvent(personId:string,propertyId:string,eventId:string,expectedRevision:number,input:PropertyEventCancellationInput){
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new PropertyEventCancellationError("forbidden");
    throw new PropertyEventCancellationError("technical");
  }
  const { error } = await auth.supabase.rpc("cancel_property_event", {p_protected_person_id:personId,p_property_id:propertyId,p_event_id:eventId,p_expected_revision:expectedRevision,p_reason:input.reason});
  if (!error) return;
  if (error.code === "42501") throw new PropertyEventCancellationError("forbidden");
  if (error.code === "P0002") throw new PropertyEventCancellationError("not_found");
  if (error.code === "40001") throw new PropertyEventCancellationError("stale_revision");
  if (error.message.includes("exercice clôturé")) throw new PropertyEventCancellationError("closed_period");
  if (error.message === "Cet événement est déjà annulé.") throw new PropertyEventCancellationError("already_cancelled");
  if (error.message.includes("origine patrimoniale de remplacement")) throw new PropertyEventCancellationError("entry_event");
  if (error.message.includes("vente active sont incohérents")) throw new PropertyEventCancellationError("inconsistent");
  if (error.code === "23514") throw new PropertyEventCancellationError("invalid");
  throw new PropertyEventCancellationError("technical");
}
export async function changePropertyArchiveState(personId:string,propertyId:string,expectedRevision:number,input:PropertyArchiveChangeInput,operation:"archive"|"restore"){
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new PropertyArchiveChangeError("forbidden");
    throw new PropertyArchiveChangeError("technical");
  }
  const rpc = operation === "archive" ? "archive_real_estate_property" : "restore_real_estate_property";
  const { error } = await auth.supabase.rpc(rpc, {p_protected_person_id:personId,p_property_id:propertyId,p_expected_revision:expectedRevision,p_reason:input.reason});
  if (!error) return;
  if (error.code === "42501") throw new PropertyArchiveChangeError("forbidden");
  if (error.code === "P0002") throw new PropertyArchiveChangeError("not_found");
  if (error.code === "40001") throw new PropertyArchiveChangeError("stale_revision");
  if (error.message === "Ce bien immobilier est déjà archivé.") throw new PropertyArchiveChangeError("already_archived");
  if (error.message === "Ce bien immobilier n’est pas archivé.") throw new PropertyArchiveChangeError("not_archived");
  if (error.message.includes("incohérent avec")) throw new PropertyArchiveChangeError("inconsistent");
  if (error.code === "23514") throw new PropertyArchiveChangeError("invalid");
  throw new PropertyArchiveChangeError("technical");
}
export async function getPatrimonyAbsenceConfirmations(personId: string): Promise<PatrimonyAbsenceConfirmationState> {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("patrimony_absence_confirmations")
    .select("*")
    .eq("protected_person_id", personId);
  if (error) throw new Error("Impossible de charger les confirmations d’absence patrimoniale.");
  return buildPatrimonyAbsenceConfirmationState(data);
}
export async function setPatrimonyAbsenceConfirmation(input: PatrimonyAbsenceConfirmationInput) {
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new PatrimonyAbsenceConfirmationError("forbidden");
    throw new PatrimonyAbsenceConfirmationError("technical");
  }
  const { data, error } = await auth.supabase.rpc("set_patrimony_absence_confirmation", {
    p_protected_person_id: input.personId,
    p_category: input.category,
    p_confirmed: input.confirmed,
  });
  if (!error) return data;
  if (error.code === "42501") throw new PatrimonyAbsenceConfirmationError("forbidden");
  if (error.code === "23514") throw new PatrimonyAbsenceConfirmationError("invalid");
  throw new PatrimonyAbsenceConfirmationError("technical");
}
export async function getDebts(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("debts").select("*").eq("protected_person_id",personId).order("status").order("creditor");if(error)throw new Error("Impossible de charger les dettes.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("debt_balances").select("*").in("debt_id",ids).is("cancelled_at",null).order("balance_date",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger les situations de dette.");return data.map(debt=>({...debt,balances:result.data.filter(balance=>balance.debt_id===debt.id)}));}
export async function getDebt(personId:string,debtId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("debts").select("*").eq("id",debtId).eq("protected_person_id",personId).maybeSingle();if(error)throw new Error("Impossible de charger la dette.");if(!data)return null;const[balancesResult,statusChangesResult,balanceChangesResult,closedPeriodsResult,staleReportsResult]=await Promise.all([supabase.from("debt_balances").select("*").eq("debt_id",debtId).order("balance_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false}),supabase.from("debt_status_changes").select("*").eq("debt_id",debtId).eq("protected_person_id",personId).order("changed_at",{ascending:false}).order("id",{ascending:false}),supabase.from("debt_balance_changes").select("*").eq("debt_id",debtId).eq("protected_person_id",personId).order("changed_at",{ascending:false}).order("id",{ascending:false}),supabase.from("management_periods").select("id,start_date,end_date").eq("protected_person_id",personId).eq("status","closed"),supabase.from("management_reports").select("id,report_year,period_start,period_end,refresh_required_at").eq("protected_person_id",personId).eq("status","generated").not("refresh_required_at","is",null).order("report_year",{ascending:false})]);if(balancesResult.error)throw new Error("Impossible de charger l’historique de la dette.");if(statusChangesResult.error)throw new Error("Impossible de charger l’historique des statuts de la dette.");if(balanceChangesResult.error)throw new Error("Impossible de charger le journal des situations de dette.");if(closedPeriodsResult.error)throw new Error("Impossible de vérifier les exercices clôturés.");if(staleReportsResult.error)throw new Error("Impossible de vérifier les projets de comptes de gestion.");return{...data,balances:balancesResult.data,statusChanges:statusChangesResult.data,balanceChanges:balanceChangesResult.data,closedPeriods:closedPeriodsResult.data,staleManagementReports:staleReportsResult.data};}
export async function saveDebt(personId:string,input:DebtInput,id?:string){const{supabase}=await getAuthenticatedUser();const payload={creditor:input.creditor,debt_type:input.debtType,designation:input.designation,start_date:input.startDate,initial_amount:input.initialAmount,initial_duration_months:input.initialDurationMonths,monthly_payment:input.monthlyPayment,interest_rate:input.interestRate,notes:input.notes};const query=id?supabase.from("debts").update(payload).eq("id",id).eq("protected_person_id",personId):supabase.from("debts").insert({...payload,protected_person_id:personId});const{error}=await query.select("id").single();if(error)throw new Error("Impossible d’enregistrer la dette.");}
export async function addDebtBalance(personId:string,debtId:string,input:DebtBalanceInput){let auth:Awaited<ReturnType<typeof getAuthenticatedUser>>;try{auth=await getAuthenticatedUser();}catch{throw new DebtBalanceError("forbidden");}const{data,error:debtError}=await auth.supabase.from("debts").select("id,status").eq("id",debtId).eq("protected_person_id",personId).maybeSingle();if(debtError)throw new DebtBalanceError("technical");if(!data)throw new DebtBalanceError("not_found");if(data.status!=="active")throw new DebtBalanceError("settled");const{error}=await auth.supabase.from("debt_balances").insert({debt_id:debtId,balance_date:input.balanceDate,remaining_balance:input.remainingBalance,remaining_duration_months:input.remainingDurationMonths});if(error)throw mapDebtBalanceError(error);}
export async function correctDebtBalance(personId:string,debtId:string,balanceId:string,expectedRevision:number,input:DebtBalanceCorrectionInput){let auth:Awaited<ReturnType<typeof getAuthenticatedUser>>;try{auth=await getAuthenticatedUser();}catch{throw new DebtBalanceError("forbidden");}const{error}=await auth.supabase.rpc("correct_debt_balance",{p_protected_person_id:personId,p_debt_id:debtId,p_debt_balance_id:balanceId,p_expected_revision:expectedRevision,p_balance_date:input.balanceDate,p_remaining_balance:input.remainingBalance,p_remaining_duration_months:input.remainingDurationMonths,p_reason:input.reason});if(error)throw mapDebtBalanceError(error);}
export async function cancelDebtBalance(personId:string,debtId:string,balanceId:string,expectedRevision:number,input:DebtBalanceCancellationInput){let auth:Awaited<ReturnType<typeof getAuthenticatedUser>>;try{auth=await getAuthenticatedUser();}catch{throw new DebtBalanceError("forbidden");}const{error}=await auth.supabase.rpc("cancel_debt_balance",{p_protected_person_id:personId,p_debt_id:debtId,p_debt_balance_id:balanceId,p_expected_revision:expectedRevision,p_reason:input.reason});if(error)throw mapDebtBalanceError(error);}
export async function settleDebt(personId:string,debtId:string,expectedRevision:number,input:DebtSettlementInput){
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new DebtSettlementError("forbidden");
    throw new DebtSettlementError("technical");
  }

  const [permissionResult,personResult,debtResult]=await Promise.all([
    auth.supabase.rpc("can_manage_protected_person",{person_id:personId}),
    auth.supabase.from("protected_persons").select("status").eq("id",personId).maybeSingle(),
    auth.supabase.from("debts").select("id,revision,status,settled_at,start_date,current_balance").eq("id",debtId).eq("protected_person_id",personId).maybeSingle(),
  ]);
  if(permissionResult.error)throw new DebtSettlementError("technical");
  if(!permissionResult.data)throw new DebtSettlementError("forbidden");
  if(personResult.error)throw new DebtSettlementError("technical");
  if(!personResult.data)throw new DebtSettlementError("not_found");
  if(personResult.data.status==="archived")throw new DebtSettlementError("archived_dossier");
  if(debtResult.error)throw new DebtSettlementError("technical");
  if(!debtResult.data)throw new DebtSettlementError("not_found");
  if(debtResult.data.revision!==expectedRevision)throw new DebtSettlementError("stale_revision");
  if(debtResult.data.status!=="active"||debtResult.data.settled_at!==null)throw new DebtSettlementError("already_settled");
  if(debtResult.data.start_date===null)throw new DebtSettlementError("missing_start_date");
  if(debtResult.data.current_balance===null)throw new DebtSettlementError("missing_zero_balance");
  if(debtResult.data.current_balance!==0)throw new DebtSettlementError("positive_balance");

  const{error}=await auth.supabase.rpc("settle_debt",{p_protected_person_id:personId,p_debt_id:debtId,p_expected_revision:expectedRevision,p_settled_at:input.settledAt,p_reason:input.reason});
  if(!error)return;
  if(error.code==="42501")throw new DebtSettlementError("forbidden");
  if(error.code==="P0002")throw new DebtSettlementError("not_found");
  if(error.code==="40001")throw new DebtSettlementError("stale_revision");
  if(error.code==="P4R01")throw new DebtSettlementError("archived_dossier");
  if(error.message.includes("Seule une dette active"))throw new DebtSettlementError("already_settled");
  if(error.message.includes("date de debut"))throw new DebtSettlementError("missing_start_date");
  if(error.message.includes("date de cloture doit etre comprise"))throw new DebtSettlementError("invalid_date");
  if(error.message.includes("exercice cloture"))throw new DebtSettlementError("closed_period");
  if(error.message.includes("situation a 0 EUR"))throw new DebtSettlementError("missing_zero_balance");
  if(error.message.includes("situation plus recente"))throw new DebtSettlementError("later_balance");
  if(error.message.includes("situation courante")||error.message.includes("incoherente"))throw new DebtSettlementError("inconsistent");
  if(error.code==="23514")throw new DebtSettlementError("invalid");
  throw new DebtSettlementError("technical");
}
