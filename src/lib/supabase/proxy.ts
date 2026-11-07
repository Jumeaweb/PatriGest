import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseConfig } from "./config";
import type { Database } from "@/types/database";

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { supabaseUrl, supabaseAnonKey } = getSupabaseConfig();

  const supabase = createServerClient<Database>(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, cacheHeaders) {
        cookiesToSet.forEach(({ name, value }) =>
          request.cookies.set(name, value),
        );

        response = NextResponse.next({ request });

        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
        Object.entries(cacheHeaders).forEach(([name, value]) =>
          response.headers.set(name, value),
        );
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  const pathname = request.nextUrl.pathname;
  const isAccessWaitingRoute = pathname.startsWith("/acces-en-attente");
  const isProtectedRoute = ["/tableau-de-bord", "/dossiers", "/administration", "/parametres", "/mon-compte", "/historique-versions", "/invitations", "/api"].some((path) =>
    pathname.startsWith(path),
  );

  if (isProtectedRoute && !data?.claims) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/connexion";
    loginUrl.search = "";
    return NextResponse.redirect(loginUrl);
  }

  if (data?.claims) {
    const userId = data.claims.sub;
    const [{ data: administrator }, { data: authorization }, trialStateResult] = await Promise.all([
      supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
      supabase.from("application_user_authorizations").select("status").eq("user_id", userId).maybeSingle(),
      supabase.rpc("get_current_account_trial_state"),
    ]);
    const hasApplicationAccess = Boolean(administrator) || authorization?.status === "active";

    if (isProtectedRoute && !hasApplicationAccess) {
      const waitingUrl = request.nextUrl.clone();
      waitingUrl.pathname = "/acces-en-attente";
      waitingUrl.search = "";
      return NextResponse.redirect(waitingUrl);
    }

    const trialState = trialStateResult.data?.[0];
    const trialRestricted = !administrator
      && trialState?.enforcement_enabled === true
      && (trialState.state === "suspended" || trialState.state === "deletion_due");
    if (isProtectedRoute && trialRestricted) {
      if (pathname.startsWith("/api")) {
        return NextResponse.json(
          { error: "L’accès métier est suspendu. Consultez votre abonnement." },
          { status: 403 },
        );
      }
      const isSubscriptionRoute = pathname === "/parametres/compte"
        && request.nextUrl.searchParams.get("vue") === "abonnement";
      if (!isSubscriptionRoute) {
        const subscriptionUrl = request.nextUrl.clone();
        subscriptionUrl.pathname = "/parametres/compte";
        subscriptionUrl.search = "?vue=abonnement";
        return NextResponse.redirect(subscriptionUrl);
      }
    }

    if (isAccessWaitingRoute && hasApplicationAccess) {
      const dashboardUrl = request.nextUrl.clone();
      dashboardUrl.pathname = "/tableau-de-bord";
      dashboardUrl.search = "";
      return NextResponse.redirect(dashboardUrl);
    }

    const isBusinessRoute = pathname.startsWith("/dossiers") || pathname.startsWith("/parametres/categories");

    if (administrator && isBusinessRoute) {
      const administrationUrl = request.nextUrl.clone();
      administrationUrl.pathname = "/administration";
      administrationUrl.search = "";
      return NextResponse.redirect(administrationUrl);
    }
  }

  return response;
}
