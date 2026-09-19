import { NextResponse, type NextRequest } from "next/server";
import { getSafeAuthCallbackNextPath } from "@/lib/auth/callback-destination";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const nextPath = getSafeAuthCallbackNextPath(request.nextUrl.searchParams.get("next"));

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      const { data: claims } = await supabase.auth.getClaims();
      const userId = claims?.claims?.sub;
      if (!userId) {
        const response = NextResponse.redirect(new URL("/connexion?erreur=confirmation", request.url));
        response.headers.set("Cache-Control", "private, no-store");
        return response;
      }

      const [{ data: authorization }, { data: administrator }] = await Promise.all([
        supabase.from("application_user_authorizations").select("status").eq("user_id", userId).maybeSingle(),
        supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
      ]);
      const hasApplicationAccess = Boolean(administrator || authorization?.status === "active");
      const authFlowPath = nextPath?.startsWith("/invitation/") || nextPath?.startsWith("/nouveau-mot-de-passe") ? nextPath : null;
      const accountPath = nextPath === "/parametres/compte" && hasApplicationAccess ? nextPath : null;
      const destination = authFlowPath ?? accountPath ?? (hasApplicationAccess ? "/tableau-de-bord" : "/acces-en-attente");
      const response = NextResponse.redirect(new URL(destination, request.url));
      response.headers.set("Cache-Control", "private, no-store");
      return response;
    }
  }

  const response = NextResponse.redirect(new URL("/connexion?erreur=confirmation", request.url));
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
