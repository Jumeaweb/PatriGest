import assert from "node:assert/strict";
import test from "node:test";

import { authUserExistsByEmail } from "./auth-user-lookup.ts";

function adminWithPages(pages, total) {
  const calls = [];
  return {
    calls,
    async listUsers(params) {
      calls.push(params);
      return { data: { users: pages[params.page - 1] ?? [], total }, error: null };
    },
  };
}

test("cherche au-delà des 1000 premiers utilisateurs", async () => {
  const firstPage = Array.from({ length: 1000 }, (_, index) => ({ email: `user-${index}@example.test` }));
  const admin = adminWithPages([firstPage, [{ email: "invite@example.test" }]], 1001);

  assert.equal(await authUserExistsByEmail(admin, "invite@example.test"), true);
  assert.deepEqual(admin.calls, [{ page: 1, perPage: 1000 }, { page: 2, perPage: 1000 }]);
});

test("compare les adresses normalisées sans distinction de casse", async () => {
  const admin = adminWithPages([[{ email: "Invite@Example.Test" }]], 1);
  assert.equal(await authUserExistsByEmail(admin, " invite@example.test "), true);
});

test("conclut à l'absence uniquement après la dernière page", async () => {
  const firstPage = Array.from({ length: 1000 }, (_, index) => ({ email: `user-${index}@example.test` }));
  const admin = adminWithPages([firstPage, [{ email: "other@example.test" }]], 1001);
  assert.equal(await authUserExistsByEmail(admin, "missing@example.test"), false);
  assert.equal(admin.calls.length, 2);
});

test("propage une erreur Auth au lieu de conclure à une absence", async () => {
  const failure = new Error("Auth indisponible");
  const admin = { async listUsers() { return { data: { users: [] }, error: failure }; } };
  await assert.rejects(authUserExistsByEmail(admin, "invite@example.test"), failure);
});
