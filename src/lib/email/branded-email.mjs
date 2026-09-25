/**
 * @typedef {Object} BrandedEmailOptions
 * @property {string} appName
 * @property {string} actionUrl
 * @property {string} actionLabel
 * @property {string} title
 * @property {string} [greeting]
 * @property {string} [eyebrow]
 * @property {readonly string[]} paragraphs
 * @property {readonly string[]} [items]
 * @property {string} [footerText]
 */

/** @param {string} value */
function escapeHtml(value) {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character] ?? character);
}

/** @param {BrandedEmailOptions} options */
export function buildBrandedEmailHtml({
  appName,
  actionUrl,
  actionLabel,
  title,
  greeting,
  eyebrow,
  paragraphs,
  items = [],
  footerText = "La gestion claire du patrimoine protégé.",
}) {
  const logoUrl = new URL("/logos/patrigest-symbol.png", actionUrl).toString();
  const paragraphHtml = paragraphs.map((paragraph) => `<p style="margin:0 0 16px">${escapeHtml(paragraph)}</p>`).join("");
  const itemsHtml = items.length
    ? `<ul style="margin:4px 0 20px;padding-left:22px">${items.map((item) => `<li style="margin:0 0 8px">${escapeHtml(item)}</li>`).join("")}</ul>`
    : "";

  return `<!doctype html>
<html lang="fr">
  <head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
  <body style="margin:0;background:#f8f6e9;color:#214660;font-family:Arial,sans-serif;line-height:1.6">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;background:#f8f6e9">
      <tr><td align="center" style="padding:24px 12px">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;border:1px solid #d9e4df;border-radius:16px;background:#ffffff;overflow:hidden">
          <tr><td align="center" style="background:#dcecea;padding:20px 24px 16px">
            <img src="${escapeHtml(logoUrl)}" width="72" alt="${escapeHtml(appName)}" style="display:block;width:72px;max-width:100%;height:auto">
            <p style="margin:6px 0 0;color:#214660;font-size:20px;font-weight:700">${escapeHtml(appName)}</p>
          </td></tr>
          <tr><td style="padding:28px 24px">
            ${greeting ? `<p style="margin:0 0 18px">${escapeHtml(greeting)}</p>` : ""}
            ${eyebrow ? `<p style="margin:0 0 8px;color:#377e84;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:.04em">${escapeHtml(eyebrow)}</p>` : ""}
            <h1 style="margin:0 0 18px;color:#214660;font-size:24px;line-height:1.3">${escapeHtml(title)}</h1>
            ${paragraphHtml}
            ${itemsHtml}
            <p style="margin:24px 0 4px">
              <a href="${escapeHtml(actionUrl)}" style="display:inline-block;border-radius:10px;background:#ea580c;color:#ffffff;padding:11px 18px;text-decoration:none;font-weight:700">${escapeHtml(actionLabel)}</a>
            </p>
          </td></tr>
          <tr><td style="border-top:1px solid #d9e4df;background:#f8f6e9;padding:16px 24px;text-align:center;color:#64748b;font-size:12px">${escapeHtml(footerText)}</td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;
}
