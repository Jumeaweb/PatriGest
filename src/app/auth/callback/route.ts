import { NextResponse, type NextRequest } from "next/server";
import { getRecoverableDossierInvitations } from "@/domains/access/services";
import { getSafeAuthCallbackNextPath } from "@/lib/auth/callback-destination";
import {
  getInvitationRecoveryDestination,
  INVITATION_RECOVERY_COOKIE,
  INVITATION_RECOVERY_COOKIE_PATH,
} from "@/lib/auth/invitation-recovery";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const nextPath = getSafeAuthCallbackNextPath(request.nextUrl.searchParams.get("next"));
  const preferredInvitationId = request.cookies.get(INVITATION_RECOVERY_COOKIE)?.value ?? null;

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
      const accountPath = (nextPath === "/parametres/compte" || nextPath === "/parametres/compte?vue=email") && hasApplicationAccess
        ? nextPath
        : null;
      let invitationRecoveryPath: string | null = null;
      if (!authFlowPath && !accountPath) {
        try {
          invitationRecoveryPath = getInvitationRecoveryDestination(
            await getRecoverableDossierInvitations(userId),
            preferredInvitationId,
          );
        } catch {
          invitationRecoveryPath = null;
        }
      }
      const destination = authFlowPath ?? accountPath ?? invitationRecoveryPath ?? (hasApplicationAccess ? "/tableau-de-bord" : "/acces-en-attente");
      const response = NextResponse.redirect(new URL(destination, request.url));
      response.cookies.set(INVITATION_RECOVERY_COOKIE, "", {
        httpOnly: true,
        sameSite: "lax",
        secure: request.nextUrl.protocol === "https:",
        path: INVITATION_RECOVERY_COOKIE_PATH,
        maxAge: 0,
      });
      response.headers.set("Cache-Control", "private, no-store");
      return response;
    }
  }

  const response = NextResponse.redirect(new URL("/connexion?erreur=confirmation", request.url));
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
