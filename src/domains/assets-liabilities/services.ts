import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { DebtBalanceInput, DebtInput, PropertyEventCancellationInput, PropertyEventCorrectionInput, PropertyEventInput, PropertyInput, PropertySalePriceCorrectionInput } from "./schemas";

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
const PROPERTY_EVENT_CLOSED_PERIOD_MESSAGE = "Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l’assistance PatriGest.";
export async function getProperties(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("protected_person_id",personId).order("status").order("designation");if(error)throw new Error("Impossible de charger le patrimoine immobilier.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("property_events").select("*").in("property_id",ids).is("cancelled_at",null).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger l’historique immobilier.");return data.map(property=>({...property,events:result.data.filter(event=>event.property_id===property.id)}));}
export async function getProperty(personId:string,propertyId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("id",propertyId).eq("protected_person_id",personId).maybeSingle();if(error)throw new Error("Impossible de charger le bien immobilier.");if(!data)return null;const eventsResult=await supabase.from("property_events").select("*").eq("property_id",propertyId).eq("protected_person_id",personId).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false});if(eventsResult.error)throw new Error("Impossible de charger l’historique immobilier.");const eventIds=eventsResult.data.map(event=>event.id);const [correctionsResult,changesResult]=eventIds.length?await Promise.all([supabase.from("property_sale_price_corrections").select("*").in("property_event_id",eventIds).order("corrected_at",{ascending:true}).order("id",{ascending:true}),supabase.from("property_event_changes").select("*").in("property_event_id",eventIds).order("changed_at",{ascending:true}).order("id",{ascending:true})]):[{data:[],error:null},{data:[],error:null}];if(correctionsResult.error)throw new Error("Impossible de charger les corrections de prix de vente.");if(changesResult.error)throw new Error("Impossible de charger les corrections d’événements.");return{...data,events:eventsResult.data.map(event=>({...event,priceCorrections:correctionsResult.data.filter(correction=>correction.property_event_id===event.id),changes:changesResult.data.filter(change=>change.property_event_id===event.id)}))};}
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
export async function getDebts(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("debts").select("*").eq("protected_person_id",personId).order("status").order("creditor");if(error)throw new Error("Impossible de charger les dettes.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("debt_balances").select("*").in("debt_id",ids).order("balance_date",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger les situations de dette.");return data.map(debt=>({...debt,balances:result.data.filter(balance=>balance.debt_id===debt.id)}));}
export async function saveDebt(personId:string,input:DebtInput,id?:string){const{supabase}=await getAuthenticatedUser();const payload={creditor:input.creditor,debt_type:input.debtType,designation:input.designation,start_date:input.startDate,initial_amount:input.initialAmount,initial_duration_months:input.initialDurationMonths,monthly_payment:input.monthlyPayment,interest_rate:input.interestRate,status:input.status,settled_at:input.settledAt,notes:input.notes};const query=id?supabase.from("debts").update(payload).eq("id",id).eq("protected_person_id",personId):supabase.from("debts").insert({...payload,protected_person_id:personId});const{error}=await query.select("id").single();if(error)throw new Error("Impossible d’enregistrer la dette.");}
export async function addDebtBalance(personId:string,debtId:string,input:DebtBalanceInput){const{supabase}=await getAuthenticatedUser();const{data}=await supabase.from("debts").select("id").eq("id",debtId).eq("protected_person_id",personId).maybeSingle();if(!data)throw new Error("Dette introuvable.");const{error}=await supabase.from("debt_balances").insert({debt_id:debtId,balance_date:input.balanceDate,remaining_balance:input.remainingBalance,remaining_duration_months:input.remainingDurationMonths});if(error)throw new Error("Impossible d’enregistrer la situation de dette.");}
