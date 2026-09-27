import { NextResponse, type NextRequest } from "next/server";
import {
  getEmailChangeConfirmationState,
  getEmailChangeResultPath,
  parseEmailChangeConfirmationParams,
} from "@/lib/auth/email-change-confirmation";
import { createClient } from "@/lib/supabase/server";

function noStoreRedirect(request: NextRequest, destination: string) {
  const response = NextResponse.redirect(new URL(destination, request.url));
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

export async function GET(request: NextRequest) {
  const confirmation = parseEmailChangeConfirmationParams(request.nextUrl.searchParams);
  if (!confirmation) return noStoreRedirect(request, getEmailChangeResultPath("error"));

  const supabase = await createClient();
  const { data, error } = await supabase.auth.verifyOtp({
    token_hash: confirmation.tokenHash,
    type: "email_change",
  });
  const state = getEmailChangeConfirmationState(error, data.user);

  return noStoreRedirect(
    request,
    getEmailChangeResultPath(state, confirmation.nextPath),
  );
}
