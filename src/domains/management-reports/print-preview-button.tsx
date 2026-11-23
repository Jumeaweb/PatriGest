"use client";

export function PrintPreviewButton() {
  return (
    <button
      type="button"
      className="button button-primary"
      onClick={() => window.print()}
    >
      Imprimer l’aperçu
    </button>
  );
}
