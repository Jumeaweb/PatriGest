function escapeHtml(value: string) {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character] ?? character);
}

export function buildApplicationActivationEmail({ appName, firstName, loginUrl }: {
  appName: string;
  firstName: string;
  loginUrl: string;
}) {
  const greeting = firstName.trim() ? `Bonjour ${firstName.trim()},` : "Bonjour,";
  return {
    subject: "Votre accès à PatriGest est activé",
    text: [
      greeting,
      `Votre inscription à ${appName} a été validée.`,
      "Vous pouvez maintenant vous connecter et commencer à utiliser l’application.",
      `Se connecter à PatriGest : ${loginUrl}`,
      "La gestion claire du patrimoine protégé.",
    ].join("\n\n"),
    html: `
      <div style="font-family:Arial,sans-serif;color:#0f172a;line-height:1.6">
        <p>${escapeHtml(greeting)}</p>
        <p>Votre inscription à ${escapeHtml(appName)} a été validée.</p>
        <p>Vous pouvez maintenant vous connecter et commencer à utiliser l’application.</p>
        <p style="margin:24px 0">
          <a href="${escapeHtml(loginUrl)}" style="display:inline-block;border-radius:10px;background:#2563eb;color:#fff;padding:11px 18px;text-decoration:none;font-weight:700">Se connecter à PatriGest</a>
        </p>
        <p style="font-size:12px;color:#64748b">La gestion claire du patrimoine protégé.</p>
      </div>
    `,
  };
}
