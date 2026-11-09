export type SignupConfirmationType = "email" | "signup";

export function parseSignupConfirmationParams(searchParams: URLSearchParams) {
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type");
  const validTokenHash = Boolean(
    tokenHash
    && tokenHash.length >= 32
    && tokenHash.length <= 512
    && !/\s/.test(tokenHash),
  );

  if ((type !== "email" && type !== "signup") || !validTokenHash) return null;

  return {
    tokenHash: tokenHash as string,
    type: type as SignupConfirmationType,
  };
}
