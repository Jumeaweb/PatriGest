import assert from "node:assert/strict";
import test from "node:test";

import { collectAllPages, selectEligibleReleaseRecipients } from "./release-notification-policy.ts";

test("seuls les comptes actifs confirmés et les administrateurs confirmés sont destinataires", () => {
  const recipients = selectEligibleReleaseRecipients({
    users: [
      { id: "active", email: "active@example.test", emailConfirmedAt: "2026-01-01" },
      { id: "pending", email: "pending@example.test", emailConfirmedAt: "2026-01-01" },
      { id: "unconfirmed", email: "unconfirmed@example.test", emailConfirmedAt: null },
      { id: "admin", email: "admin@example.test", emailConfirmedAt: "2026-01-01" },
      { id: "empty", email: "", emailConfirmedAt: "2026-01-01" },
    ],
    activeUserIds: new Set(["active", "unconfirmed"]),
    administratorIds: new Set(["admin"]),
  });
  assert.deepEqual(recipients.map((recipient) => recipient.userId), ["active", "admin"]);
});

test("un administrateur également actif est dédupliqué par user_id", () => {
  const recipients = selectEligibleReleaseRecipients({
    users: [{ id: "both", email: "both@example.test", emailConfirmedAt: "2026-01-01" }],
    activeUserIds: new Set(["both"]),
    administratorIds: new Set(["both"]),
  });
  assert.equal(recipients.length, 1);
});

test("la pagination Auth dépasse 1000 utilisateurs sans troncature", async () => {
  const source = Array.from({ length: 1205 }, (_, index) => ({ id: index }));
  const calls = [];
  const result = await collectAllPages(async (page, perPage) => {
    calls.push({ page, perPage });
    return source.slice((page - 1) * perPage, page * perPage);
  });
  assert.equal(result.length, 1205);
  assert.deepEqual(calls, [{ page: 1, perPage: 1000 }, { page: 2, perPage: 1000 }]);
});
