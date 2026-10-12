import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { DebtBalanceInput, DebtInput, PropertyEventInput, PropertyEventUpdateInput, PropertyInput } from "./schemas";

export type PropertyEventUpdateErrorCode = "forbidden" | "not_found" | "sale" | "closed_period" | "technical";
export class PropertyEventUpdateError extends Error {
  constructor(readonly code: PropertyEventUpdateErrorCode) { super(code); this.name = "PropertyEventUpdateError"; }
}

async function ensurePropertyEventDateIsOpen(supabase: Awaited<ReturnType<typeof getAuthenticatedUser>>["supabase"], personId: string, eventDate: string) {
  const { data, error } = await supabase.from("management_periods").select("id").eq("protected_person_id", personId).eq("status", "closed").lte("start_date", eventDate).gte("end_date", eventDate).limit(1);
  if (error) throw new PropertyEventUpdateError("technical");
  if (data.length) throw new PropertyEventUpdateError("closed_period");
}
export async function getProperties(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("protected_person_id",personId).order("status").order("designation");if(error)throw new Error("Impossible de charger le patrimoine immobilier.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("property_events").select("*").in("property_id",ids).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger l’historique immobilier.");return data.map(property=>({...property,events:result.data.filter(event=>event.property_id===property.id)}));}
export async function getProperty(personId:string,propertyId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("real_estate_properties").select("*").eq("id",propertyId).eq("protected_person_id",personId).maybeSingle();if(error)throw new Error("Impossible de charger le bien immobilier.");if(!data)return null;const eventsResult=await supabase.from("property_events").select("*").eq("property_id",propertyId).eq("protected_person_id",personId).order("event_date",{ascending:false}).order("created_at",{ascending:false}).order("id",{ascending:false});if(eventsResult.error)throw new Error("Impossible de charger l’historique immobilier.");return{...data,events:eventsResult.data};}
export async function saveProperty(personId:string,input:PropertyInput,id?:string){const{supabase}=await getAuthenticatedUser();const payload={property_type:input.propertyType,designation:input.designation,address_line1:input.addressLine1,address_line2:input.addressLine2,postal_code:input.postalCode,city:input.city,country:input.country,entry_date:input.entryDate,entry_mode:input.entryMode,estimated_value:input.estimatedValue,valuation_date:input.valuationDate,status:input.status,disposal_date:input.disposalDate,notes:input.notes};const query=id?supabase.from("real_estate_properties").update(payload).eq("id",id).eq("protected_person_id",personId):supabase.from("real_estate_properties").insert({...payload,protected_person_id:personId});const{error}=await query.select("id").single();if(error)throw new Error("Impossible d’enregistrer le bien immobilier.");}
export async function addPropertyEvent(personId:string,propertyId:string,input:PropertyEventInput){const{supabase}=await getAuthenticatedUser();const{error}=await supabase.from("property_events").insert({property_id:propertyId,protected_person_id:personId,event_type:input.eventType,event_date:input.eventDate,description:input.description,amount:input.amount,document_reference:input.documentReference});if(error)throw new Error("Impossible d’enregistrer l’événement immobilier.");}
export async function updatePropertyEvent(personId:string,propertyId:string,eventId:string,input:PropertyEventUpdateInput){
  let auth: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try { auth = await getAuthenticatedUser(); }
  catch (error) {
    if (error instanceof Error && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) throw new PropertyEventUpdateError("forbidden");
    throw new PropertyEventUpdateError("technical");
  }
  const { supabase } = auth;
  const { data: canManage, error: permissionError } = await supabase.rpc("can_manage_protected_person", { person_id: personId });
  if (permissionError) throw new PropertyEventUpdateError("technical");
  if (!canManage) throw new PropertyEventUpdateError("forbidden");
  const { data: existing, error: lookupError } = await supabase.from("property_events").select("id,event_type,event_date").eq("id",eventId).eq("property_id",propertyId).eq("protected_person_id",personId).maybeSingle();
  if (lookupError) throw new PropertyEventUpdateError("technical");
  if (!existing) throw new PropertyEventUpdateError("not_found");
  if (existing.event_type === "sale" || input.eventType === ("sale" as string)) throw new PropertyEventUpdateError("sale");
  await ensurePropertyEventDateIsOpen(supabase, personId, existing.event_date);
  if (input.eventDate !== existing.event_date) await ensurePropertyEventDateIsOpen(supabase, personId, input.eventDate);
  const { data: updated, error: updateError } = await supabase.from("property_events").update({event_type:input.eventType,event_date:input.eventDate,description:input.description,amount:input.amount,document_reference:input.documentReference}).eq("id",eventId).eq("property_id",propertyId).eq("protected_person_id",personId).neq("event_type","sale").select("id").maybeSingle();
  if (updateError) throw new PropertyEventUpdateError("technical");
  if (!updated) throw new PropertyEventUpdateError("not_found");
}
export async function getDebts(personId:string){const{supabase}=await getAuthenticatedUser();const{data,error}=await supabase.from("debts").select("*").eq("protected_person_id",personId).order("status").order("creditor");if(error)throw new Error("Impossible de charger les dettes.");const ids=data.map(v=>v.id);const result=ids.length?await supabase.from("debt_balances").select("*").in("debt_id",ids).order("balance_date",{ascending:false}):{data:[],error:null};if(result.error)throw new Error("Impossible de charger les situations de dette.");return data.map(debt=>({...debt,balances:result.data.filter(balance=>balance.debt_id===debt.id)}));}
export async function saveDebt(personId:string,input:DebtInput,id?:string){const{supabase}=await getAuthenticatedUser();const payload={creditor:input.creditor,debt_type:input.debtType,designation:input.designation,start_date:input.startDate,initial_amount:input.initialAmount,initial_duration_months:input.initialDurationMonths,monthly_payment:input.monthlyPayment,interest_rate:input.interestRate,status:input.status,settled_at:input.settledAt,notes:input.notes};const query=id?supabase.from("debts").update(payload).eq("id",id).eq("protected_person_id",personId):supabase.from("debts").insert({...payload,protected_person_id:personId});const{error}=await query.select("id").single();if(error)throw new Error("Impossible d’enregistrer la dette.");}
export async function addDebtBalance(personId:string,debtId:string,input:DebtBalanceInput){const{supabase}=await getAuthenticatedUser();const{data}=await supabase.from("debts").select("id").eq("id",debtId).eq("protected_person_id",personId).maybeSingle();if(!data)throw new Error("Dette introuvable.");const{error}=await supabase.from("debt_balances").insert({debt_id:debtId,balance_date:input.balanceDate,remaining_balance:input.remainingBalance,remaining_duration_months:input.remainingDurationMonths});if(error)throw new Error("Impossible d’enregistrer la situation de dette.");}
